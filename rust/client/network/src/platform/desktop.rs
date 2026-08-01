//! Zenoh Native (UDP/TCP) - デスクトップ・モバイル
//!
//! - Publisher は key（＋ congestion モード）ごとに 1 度だけ declare して再利用する
//! - セッション切断を検知したら指数バックオフで再接続し、subscriber を張り直す

use futures::future::{select, Either};
use futures_timer::Delay;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use zenoh::config::Config;
use zenoh::pubsub::Publisher;
use zenoh::qos::CongestionControl;
use zenoh::{Session, Wait};

const SHUTDOWN_POLL_MS: u64 = 100;
const RECONNECT_INIT_MS: u64 = 500;
const RECONNECT_MAX_MS: u64 = 8_000;
const RECONNECT_FACTOR: u64 = 2;

struct SessionState {
    session: Session,
    /// 既定 congestion（Block）の publisher キャッシュ。
    publishers: HashMap<String, Publisher<'static>>,
    /// `CongestionControl::Drop` の publisher キャッシュ。
    publishers_drop: HashMap<String, Publisher<'static>>,
    /// 再接続のたびに増える。subscriber が古い session を捨てる判定に使う。
    generation: u64,
}

/// Zenoh セッションのラッパー。publish / subscribe を抽象化。
pub struct ClientSession {
    connect_config: String,
    state: Arc<Mutex<SessionState>>,
}

impl ClientSession {
    /// connect_config: 接続先（例: "tcp/127.0.0.1:7447"）。空ならデフォルト（scouting）。
    pub fn open(connect_config: &str) -> Result<Self, String> {
        let session = open_session(connect_config)?;
        Ok(Self {
            connect_config: connect_config.to_string(),
            state: Arc::new(Mutex::new(SessionState {
                session,
                publishers: HashMap::new(),
                publishers_drop: HashMap::new(),
                generation: 0,
            })),
        })
    }

    pub fn put(&self, key: &str, payload: &[u8]) -> Result<(), String> {
        self.publish(key, payload, CongestionMode::Default, true)
    }

    pub fn put_drop(&self, key: &str, payload: &[u8]) -> Result<(), String> {
        // put 自体の失敗は握りつぶす（従来どおり）。declare / 再接続失敗は Err。
        self.publish(key, payload, CongestionMode::Drop, false)
    }

    pub fn spawn_subscriber<F>(
        &self,
        key: &str,
        shutdown: Arc<AtomicBool>,
        on_payload: F,
    ) -> thread::JoinHandle<()>
    where
        F: Fn(Vec<u8>) + Send + 'static,
    {
        let session = Self {
            connect_config: self.connect_config.clone(),
            state: Arc::clone(&self.state),
        };
        let key = key.to_string();
        thread::spawn(move || {
            let mut backoff_ms = RECONNECT_INIT_MS;
            while !shutdown.load(Ordering::SeqCst) {
                let (zenoh_session, generation) = {
                    match session.state.lock() {
                        Ok(guard) => (guard.session.clone(), guard.generation),
                        Err(e) => {
                            log::error!("[zenoh] subscriber state lock poisoned: {e}");
                            return;
                        }
                    }
                };

                match run_subscriber_until_disconnect(
                    &zenoh_session,
                    &key,
                    generation,
                    &session.state,
                    &shutdown,
                    &on_payload,
                ) {
                    Ok(()) if shutdown.load(Ordering::SeqCst) => break,
                    Ok(()) | Err(_) => {
                        if shutdown.load(Ordering::SeqCst) {
                            break;
                        }
                        log::warn!(
                            "[zenoh] subscriber disconnected on {key}; reconnecting (backoff={backoff_ms}ms)"
                        );
                        match session.reconnect_with_backoff(&shutdown, backoff_ms) {
                            Ok(()) => {
                                log::info!("[zenoh] subscriber reconnected; resubscribing to {key}");
                                backoff_ms = RECONNECT_INIT_MS;
                            }
                            Err(e) => {
                                if shutdown.load(Ordering::SeqCst) {
                                    break;
                                }
                                log::error!("[zenoh] reconnect aborted: {e}");
                                if sleep_with_shutdown(
                                    Duration::from_millis(backoff_ms),
                                    &shutdown,
                                )
                                .is_err()
                                {
                                    break;
                                }
                                backoff_ms = next_backoff(backoff_ms);
                            }
                        }
                    }
                }
            }
        })
    }

    fn publish(
        &self,
        key: &str,
        payload: &[u8],
        mode: CongestionMode,
        report_put_err: bool,
    ) -> Result<(), String> {
        match self.publish_once(key, payload, mode, report_put_err) {
            Ok(()) => Ok(()),
            Err(e) if looks_like_session_error(&e) => {
                log::warn!("[zenoh] publish session error ({e}); recovering session");
                self.try_recover_session()?;
                self.publish_once(key, payload, mode, report_put_err)
            }
            Err(e) => Err(e),
        }
    }

    fn publish_once(
        &self,
        key: &str,
        payload: &[u8],
        mode: CongestionMode,
        report_put_err: bool,
    ) -> Result<(), String> {
        let mut state = self
            .state
            .lock()
            .map_err(|e| format!("session state lock poisoned: {e}"))?;

        if state.session.is_closed() {
            return Err("session closed".to_string());
        }

        // Session は Arc なので clone は軽い。maps への &mut と同時借用を避ける。
        let session = state.session.clone();
        let put_result = match mode {
            CongestionMode::Default => {
                let publisher = get_or_declare_publisher(
                    &session,
                    &mut state.publishers,
                    key,
                    CongestionControl::DEFAULT,
                )?;
                publisher.put(payload).wait()
            }
            CongestionMode::Drop => {
                let publisher = get_or_declare_publisher(
                    &session,
                    &mut state.publishers_drop,
                    key,
                    CongestionControl::Drop,
                )?;
                publisher.put(payload).wait()
            }
        };

        match put_result {
            Ok(()) => Ok(()),
            Err(e) if report_put_err => Err(format!("put failed: {e}")),
            Err(_) => Ok(()),
        }
    }

    /// put ホットパス向け: 現セッションを閉じて 1 回だけ open し直す。
    fn try_recover_session(&self) -> Result<(), String> {
        self.close_current();
        let new_session = open_session(&self.connect_config)?;
        self.install_session(new_session);
        log::info!("[zenoh] session recovered");
        Ok(())
    }

    /// subscriber 向け: 閉じてから指数バックオフで open を繰り返す。
    fn reconnect_with_backoff(
        &self,
        shutdown: &AtomicBool,
        initial_backoff_ms: u64,
    ) -> Result<(), String> {
        self.close_current();
        let mut delay_ms = initial_backoff_ms.max(RECONNECT_INIT_MS);
        loop {
            if shutdown.load(Ordering::SeqCst) {
                return Err("shutdown during reconnect".to_string());
            }

            {
                let state = self
                    .state
                    .lock()
                    .map_err(|e| format!("session state lock poisoned: {e}"))?;
                if !state.session.is_closed() {
                    return Ok(());
                }
            }

            match open_session(&self.connect_config) {
                Ok(session) => {
                    self.install_session(session);
                    return Ok(());
                }
                Err(e) => {
                    log::warn!("[zenoh] reconnect open failed: {e}; retry in {delay_ms}ms");
                    sleep_with_shutdown(Duration::from_millis(delay_ms), shutdown)?;
                    delay_ms = next_backoff(delay_ms);
                }
            }
        }
    }

    fn close_current(&self) {
        let Ok(mut state) = self.state.lock() else {
            return;
        };
        state.publishers.clear();
        state.publishers_drop.clear();
        if !state.session.is_closed() {
            let _ = state.session.close().wait();
        }
    }

    fn install_session(&self, new_session: Session) {
        let Ok(mut state) = self.state.lock() else {
            return;
        };
        if !state.session.is_closed() {
            // 別スレッドが先に復旧済み。余分なセッションは捨てる。
            drop(new_session);
            return;
        }
        state.publishers.clear();
        state.publishers_drop.clear();
        state.session = new_session;
        state.generation = state.generation.wrapping_add(1);
    }
}

#[derive(Clone, Copy)]
enum CongestionMode {
    Default,
    Drop,
}

fn open_session(connect_config: &str) -> Result<Session, String> {
    let mut config = Config::default();
    if !connect_config.is_empty() {
        // Elixir Network.ZenohBridge と同様に zenohd へ接続する **client** モードを明示する。
        // connect/endpoints のみ指定した場合、既定は peer に寄り、PUT がルータ上の
        // 購読者（サーバー側 Zenohex subscriber）に届かず、フレーム受信だけ成功する、
        // といった片方向だけ通る状態になり得る。
        config
            .insert_json5("mode", r#""client""#)
            .map_err(|e| format!("zenoh mode config failed: {e}"))?;
        config
            .insert_json5(
                "connect/endpoints",
                format!(r#"["{}"]"#, connect_config).as_str(),
            )
            .map_err(|e| format!("zenoh connect config failed: {e}"))?;
        log::info!("[zenoh] session config: mode=client connect/endpoints=[{connect_config}]");
    }
    zenoh::open(config)
        .wait()
        .map_err(|e| format!("zenoh open failed: {e}"))
}

fn get_or_declare_publisher<'a>(
    session: &Session,
    cache: &'a mut HashMap<String, Publisher<'static>>,
    key: &str,
    congestion: CongestionControl,
) -> Result<&'a Publisher<'static>, String> {
    if !cache.contains_key(key) {
        let owned_key = key.to_string();
        let publisher = session
            .declare_publisher(owned_key)
            .congestion_control(congestion)
            .wait()
            .map_err(|e| format!("publisher declare failed: {e}"))?;
        cache.insert(key.to_string(), publisher);
    }
    cache
        .get(key)
        .ok_or_else(|| "publisher cache insert vanished".to_string())
}

fn run_subscriber_until_disconnect<F>(
    session: &Session,
    key_expr: &str,
    generation: u64,
    state: &Mutex<SessionState>,
    shutdown: &AtomicBool,
    on_payload: &F,
) -> Result<(), String>
where
    F: Fn(Vec<u8>) + Send,
{
    if session.is_closed() {
        return Err("session closed".to_string());
    }

    let subscriber = session
        .declare_subscriber(key_expr)
        .wait()
        .map_err(|e| format!("subscribe failed: {e}"))?;

    log::info!("[zenoh subscriber] subscribed to {key_expr} (generation={generation})");

    while !shutdown.load(Ordering::SeqCst) {
        if session.is_closed() {
            return Err("session closed".to_string());
        }
        if let Ok(guard) = state.lock() {
            if guard.generation != generation {
                return Err("session replaced".to_string());
            }
        }

        let recv_fut = subscriber.recv_async();
        let timeout = Delay::new(Duration::from_millis(SHUTDOWN_POLL_MS));

        match futures::executor::block_on(select(recv_fut, timeout)) {
            Either::Left((Ok(sample), _)) => {
                let payload = sample.payload().to_bytes();
                on_payload(payload.to_vec());
            }
            Either::Left((Err(e), _)) => {
                return Err(format!("recv error: {e}"));
            }
            Either::Right((_, _)) => {}
        }
    }
    Ok(())
}

fn looks_like_session_error(err: &str) -> bool {
    let e = err.to_ascii_lowercase();
    e.contains("session closed")
        || e.contains("session replaced")
        || e.contains("disconnected")
        || e.contains("not connected")
        || e.contains("connection refused")
        || e.contains("broken pipe")
        || e.contains("reset by peer")
        || e.contains("publisher declare failed")
}

fn next_backoff(current_ms: u64) -> u64 {
    current_ms
        .saturating_mul(RECONNECT_FACTOR)
        .min(RECONNECT_MAX_MS)
}

fn sleep_with_shutdown(total: Duration, shutdown: &AtomicBool) -> Result<(), String> {
    let mut remaining = total;
    while !remaining.is_zero() {
        if shutdown.load(Ordering::SeqCst) {
            return Err("shutdown during reconnect backoff".to_string());
        }
        let slice = remaining.min(Duration::from_millis(SHUTDOWN_POLL_MS));
        thread::sleep(slice);
        remaining = remaining.saturating_sub(slice);
    }
    Ok(())
}
