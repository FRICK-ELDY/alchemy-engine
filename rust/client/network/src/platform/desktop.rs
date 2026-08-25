//! Zenoh Native (UDP/TCP) - デスクトップ・モバイル
//!
//! - Publisher は key（＋ congestion モード）ごとに 1 度だけ declare して再利用する
//! - セッション切断を検知したら指数バックオフで再接続し、subscriber を張り直す
//! - put / close のネットワーク I/O 中は state ロックを持たない（描画スレッドのスタッター回避）

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use zenoh::config::Config;
use zenoh::handlers::RingChannel;
use zenoh::pubsub::Publisher;
use zenoh::qos::CongestionControl;
use zenoh::{Session, Wait};

const SHUTDOWN_POLL_MS: u64 = 100;
const RECONNECT_INIT_MS: u64 = 500;
const RECONNECT_MAX_MS: u64 = 8_000;
const RECONNECT_FACTOR: u64 = 2;

struct SessionState {
    /// 再接続の close 中は `None`（ロック外の `close().wait()` 中に古い publisher が
    /// キャッシュへ戻るのを防ぐ）。
    session: Option<Session>,
    /// 既定 congestion（Block）の publisher キャッシュ。
    /// `Arc` で持ち、ロック外の `put().wait()` に渡す（Publisher 自体は Clone 不可）。
    publishers: HashMap<String, Arc<Publisher<'static>>>,
    /// `CongestionControl::Drop` の publisher キャッシュ。
    publishers_drop: HashMap<String, Arc<Publisher<'static>>>,
    /// 再接続のたびに増える。subscriber が古い session を捨てる判定に使う。
    generation: u64,
}

impl SessionState {
    fn has_live_session(&self) -> bool {
        self.session.as_ref().is_some_and(|s| !s.is_closed())
    }
}

/// Zenoh セッションのラッパー。publish / subscribe を抽象化。
#[derive(Clone)]
pub struct ClientSession {
    connect_config: String,
    state: Arc<Mutex<SessionState>>,
    /// 再接続の単一実行用。復旧済みセッションを別スレッドが close し直すのを防ぐ。
    reconnect_gate: Arc<Mutex<()>>,
}

impl ClientSession {
    /// connect_config: 接続先（例: "tcp/127.0.0.1:7447"）。空ならデフォルト（scouting）。
    pub fn open(connect_config: &str) -> Result<Self, String> {
        let session = open_session(connect_config)?;
        Ok(Self {
            connect_config: connect_config.to_string(),
            state: Arc::new(Mutex::new(SessionState {
                session: Some(session),
                publishers: HashMap::new(),
                publishers_drop: HashMap::new(),
                generation: 0,
            })),
            reconnect_gate: Arc::new(Mutex::new(())),
        })
    }

    pub fn put(&self, key: &str, payload: &[u8]) -> Result<(), String> {
        self.publish(key, payload, CongestionMode::Default, true)
    }

    pub fn put_drop(&self, key: &str, payload: &[u8]) -> Result<(), String> {
        // ホットパス: 切断中も毎フレーム呼ばれるため、session closed は握りつぶす。
        // 再接続は subscriber 側の指数バックオフに任せる（描画スレッドを塞がない）。
        match self.publish(key, payload, CongestionMode::Drop, false) {
            Ok(()) => Ok(()),
            Err(e) if e.contains("session closed") => Ok(()),
            Err(e) => Err(e),
        }
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
        let session = self.clone();
        let key = key.to_string();
        thread::spawn(move || {
            while !shutdown.load(Ordering::SeqCst) {
                let (zenoh_session, generation) = {
                    match session.state.lock() {
                        Ok(guard) => match guard.session.clone() {
                            Some(s) => (s, guard.generation),
                            None => {
                                // close 進行中。再接続ループへ。
                                drop(guard);
                                if shutdown.load(Ordering::SeqCst) {
                                    break;
                                }
                                log::warn!(
                                    "[zenoh] subscriber has no session on {key}; reconnecting"
                                );
                                if let Err(e) =
                                    session.reconnect_with_backoff(&shutdown, RECONNECT_INIT_MS)
                                {
                                    if !shutdown.load(Ordering::SeqCst) {
                                        log::error!("[zenoh] reconnect aborted: {e}");
                                    }
                                    break;
                                }
                                continue;
                            }
                        },
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
                    Err(e) if e.contains("lock poisoned") => {
                        log::error!("[zenoh] subscriber aborted: {e}");
                        break;
                    }
                    Ok(()) | Err(_) => {
                        if shutdown.load(Ordering::SeqCst) {
                            break;
                        }
                        log::warn!("[zenoh] subscriber disconnected on {key}; reconnecting");
                        // バックオフは reconnect_with_backoff 内のみ。Err は shutdown / poison。
                        if let Err(e) = session.reconnect_with_backoff(&shutdown, RECONNECT_INIT_MS)
                        {
                            if !shutdown.load(Ordering::SeqCst) {
                                log::error!("[zenoh] reconnect aborted: {e}");
                            }
                            break;
                        }
                        log::info!("[zenoh] subscriber reconnected; resubscribing to {key}");
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
                log::warn!("[zenoh] publish session error ({e}); invalidating session");
                // try_recover_session は常に Err（再接続は subscriber 側）。unreachable を避ける。
                self.try_recover_session()
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
        let map_put_err = |e| {
            if report_put_err {
                Err(format!("put failed: {e}"))
            } else {
                Ok(())
            }
        };

        let (session, maybe_publisher, generation) = {
            let state = self
                .state
                .lock()
                .map_err(|e| format!("session state lock poisoned: {e}"))?;

            let Some(session) = state.session.clone() else {
                return Err("session closed".to_string());
            };
            if session.is_closed() {
                return Err("session closed".to_string());
            }

            let cache = match mode {
                CongestionMode::Default => &state.publishers,
                CongestionMode::Drop => &state.publishers_drop,
            };

            (session, cache.get(key).cloned(), state.generation)
        };
        // ここまででロック解放。以降の wait() は描画スレッドを他送信と直列化しない。

        if let Some(publisher) = maybe_publisher {
            return match publisher.put(payload).wait() {
                Ok(()) => Ok(()),
                Err(e) => map_put_err(e),
            };
        }

        let congestion = match mode {
            CongestionMode::Default => CongestionControl::DEFAULT,
            CongestionMode::Drop => CongestionControl::Drop,
        };

        let publisher = session
            .declare_publisher(key.to_string())
            .congestion_control(congestion)
            .wait()
            .map_err(|e| format!("publisher declare failed: {e}"))?;
        let publisher = Arc::new(publisher);

        let put_result = match publisher.put(payload).wait() {
            Ok(()) => Ok(()),
            Err(e) => map_put_err(e),
        };

        if let Ok(mut state) = self.state.lock() {
            // 再接続で generation が進んでいたら、古い session 由来の publisher は捨てる。
            if state.generation == generation && state.has_live_session() {
                let cache = match mode {
                    CongestionMode::Default => &mut state.publishers,
                    CongestionMode::Drop => &mut state.publishers_drop,
                };
                cache.entry(key.to_string()).or_insert(publisher);
            }
        }

        put_result
    }

    /// put 経路向け: 壊れたセッションを無効化するだけ。
    ///
    /// `open_session` は数秒ブロックし得るため描画スレッドでは行わない。
    /// 再接続は subscriber 側の `reconnect_with_backoff` に完全に委ねる。
    fn try_recover_session(&self) -> Result<(), String> {
        let gen_before = self.generation()?;
        // close().wait() も描画を止め得るので、take だけして close は別スレッドへ。
        let session_to_close = {
            let Ok(mut state) = self.state.lock() else {
                return Err("session closed".to_string());
            };
            if state.generation != gen_before {
                return Err("session closed".to_string());
            }
            state.publishers.clear();
            state.publishers_drop.clear();
            state.session.take()
        };
        if let Some(session) = session_to_close {
            let _ = thread::Builder::new()
                .name("zenoh-session-close".into())
                .spawn(move || {
                    let _ = session.close().wait();
                });
        }
        Err("session closed".to_string())
    }

    /// subscriber 向け: 閉じてから指数バックオフで open を繰り返す。
    fn reconnect_with_backoff(
        &self,
        shutdown: &AtomicBool,
        initial_backoff_ms: u64,
    ) -> Result<(), String> {
        let gen_before = self.generation()?;
        let _gate = self
            .reconnect_gate
            .lock()
            .map_err(|e| format!("reconnect gate poisoned: {e}"))?;

        {
            let state = self
                .state
                .lock()
                .map_err(|e| format!("session state lock poisoned: {e}"))?;
            // 待ちの間に別スレッドが復旧済みなら、そのセッションを閉じない。
            if state.has_live_session() && state.generation != gen_before {
                return Ok(());
            }
        }

        self.close_current_if_generation(gen_before);
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
                if state.has_live_session() {
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

    fn generation(&self) -> Result<u64, String> {
        self.state
            .lock()
            .map(|s| s.generation)
            .map_err(|e| format!("session state lock poisoned: {e}"))
    }

    /// `expected_generation` のままだったときだけ close する（新しい世代を壊さない）。
    /// `close().wait()` はロック外で行い、描画スレッドのロック待ちを防ぐ。
    /// ロック内では `session.take()` し、close 完了前に古い publisher がキャッシュへ
    /// 戻るのを防ぐ。
    fn close_current_if_generation(&self, expected_generation: u64) {
        let session_to_close = {
            let Ok(mut state) = self.state.lock() else {
                return;
            };
            if state.generation != expected_generation {
                return;
            }
            state.publishers.clear();
            state.publishers_drop.clear();
            state.session.take()
        };

        if let Some(session) = session_to_close {
            let _ = session.close().wait();
        }
    }

    fn install_session(&self, new_session: Session) {
        let Ok(mut state) = self.state.lock() else {
            return;
        };
        if state.has_live_session() {
            // 別スレッドが先に復旧済み。余分なセッションは捨てる。
            drop(new_session);
            return;
        }
        state.publishers.clear();
        state.publishers_drop.clear();
        state.session = Some(new_session);
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
    let connect_config = prefer_udp_if_remote(connect_config);
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

/// loopback 以外の `tcp/` は UDP に読み替える。
/// テザリング等の TCP バッファ膨張でフレーム遅延が時間とともに伸びるのを避ける。
fn prefer_udp_if_remote(connect_config: &str) -> String {
    let Some(rest) = connect_config.strip_prefix("tcp/") else {
        return connect_config.to_string();
    };
    let host = zenoh_endpoint_host(rest);
    if is_loopback_host(host) || is_loopback_host(rest) {
        return connect_config.to_string();
    }
    let udp = format!("udp/{rest}");
    log::info!("[zenoh] remote tcp endpoint rewritten to {udp} to avoid TCP bufferbloat");
    udp
}

/// `host:port` / `[ipv6]:port` からホスト部分を取る。ポート省略の IPv6 もブラケットごと残す。
fn zenoh_endpoint_host(rest: &str) -> &str {
    if rest.starts_with('[') {
        if let Some(end_idx) = rest.find(']') {
            &rest[..=end_idx]
        } else {
            rest
        }
    } else {
        rest.rsplit_once(':').map(|(h, _)| h).unwrap_or(rest)
    }
}

fn is_loopback_host(host: &str) -> bool {
    matches!(
        host,
        "127.0.0.1" | "localhost" | "[::1]" | "::1" | "0.0.0.0" | "[::]"
    )
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

    // 容量 1 なので未消費の古いフレームは到着時点で捨てる。受信側で追加ドレインしない。
    let subscriber = session
        .declare_subscriber(key_expr)
        .with(RingChannel::new(1))
        .wait()
        .map_err(|e| format!("subscribe failed: {e}"))?;

    log::info!("[zenoh subscriber] subscribed to {key_expr} (generation={generation})");

    while !shutdown.load(Ordering::SeqCst) {
        if session.is_closed() {
            return Err("session closed".to_string());
        }
        // 世代チェックだけロックし、recv 待ちの前に必ず解放する。
        // ここを握ったままだと描画スレッドの put_drop が最大 SHUTDOWN_POLL_MS 詰まる。
        let session_replaced = {
            let guard = state
                .lock()
                .map_err(|e| format!("session state lock poisoned: {e}"))?;
            guard.generation != generation || !guard.has_live_session()
        };
        if session_replaced {
            return Err("session replaced".to_string());
        }

        // RingChannelHandler::recv_timeout は ZResult<Option<Sample>>。
        // タイムアウトは Ok(None)（flume の RecvTimeoutError は返さない）。
        match subscriber.recv_timeout(Duration::from_millis(SHUTDOWN_POLL_MS)) {
            Ok(Some(sample)) => {
                let payload = sample.payload().to_bytes();
                on_payload(payload.to_vec());
            }
            Ok(None) => {}
            Err(e) => {
                return Err(format!("recv error: {e}"));
            }
        }
    }
    Ok(())
}

fn looks_like_session_error(err: &str) -> bool {
    let e = err.to_ascii_lowercase();
    // session closed / replaced は subscriber 側が既に再接続中のことが多い。
    // 送信ホットパスで同期 recover すると描画スレッドがフレームごとにブロックするので除外する。
    if e.contains("session closed") || e.contains("session replaced") {
        return false;
    }
    e.contains("disconnected")
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

#[cfg(test)]
mod tests {
    use super::{is_loopback_host, prefer_udp_if_remote, zenoh_endpoint_host};

    #[test]
    fn loopback_tcp_is_kept() {
        assert_eq!(
            prefer_udp_if_remote("tcp/127.0.0.1:7447"),
            "tcp/127.0.0.1:7447"
        );
        assert_eq!(
            prefer_udp_if_remote("tcp/localhost:7447"),
            "tcp/localhost:7447"
        );
        assert_eq!(prefer_udp_if_remote("tcp/[::1]:7447"), "tcp/[::1]:7447");
        assert_eq!(prefer_udp_if_remote("tcp/[::]:7447"), "tcp/[::]:7447");
        assert_eq!(prefer_udp_if_remote("tcp/[::1]"), "tcp/[::1]");
        assert_eq!(prefer_udp_if_remote("tcp/::1"), "tcp/::1");
    }

    #[test]
    fn remote_tcp_is_rewritten_to_udp() {
        assert_eq!(
            prefer_udp_if_remote("tcp/192.168.200.8:7447"),
            "udp/192.168.200.8:7447"
        );
        assert_eq!(
            prefer_udp_if_remote("tcp/172.20.10.2:7447"),
            "udp/172.20.10.2:7447"
        );
        assert_eq!(
            prefer_udp_if_remote("tcp/[2001:db8::1]:7447"),
            "udp/[2001:db8::1]:7447"
        );
        assert_eq!(
            prefer_udp_if_remote("tcp/[2001:db8::1]"),
            "udp/[2001:db8::1]"
        );
    }

    #[test]
    fn udp_and_empty_are_unchanged() {
        assert_eq!(
            prefer_udp_if_remote("udp/192.168.200.8:7447"),
            "udp/192.168.200.8:7447"
        );
        assert_eq!(prefer_udp_if_remote(""), "");
    }

    #[test]
    fn loopback_hosts() {
        assert!(is_loopback_host("127.0.0.1"));
        assert!(is_loopback_host("localhost"));
        assert!(is_loopback_host("[::1]"));
        assert!(is_loopback_host("::1"));
        assert!(is_loopback_host("[::]"));
        assert!(!is_loopback_host("192.168.200.8"));
        assert!(!is_loopback_host("[2001:db8::1]"));
    }

    #[test]
    fn zenoh_endpoint_host_keeps_ipv6_brackets() {
        assert_eq!(zenoh_endpoint_host("127.0.0.1:7447"), "127.0.0.1");
        assert_eq!(zenoh_endpoint_host("[::1]:7447"), "[::1]");
        assert_eq!(zenoh_endpoint_host("[::1]"), "[::1]");
        assert_eq!(zenoh_endpoint_host("[2001:db8::1]:7447"), "[2001:db8::1]");
        assert_eq!(zenoh_endpoint_host("localhost"), "localhost");
    }
}
