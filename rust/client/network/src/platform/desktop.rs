//! Zenoh Native (UDP/TCP) - デスクトップ・モバイル

use futures::future::{select, Either};
use futures_timer::Delay;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;
use zenoh::config::Config;
use zenoh::qos::CongestionControl;
use zenoh::{Session, Wait};

const SHUTDOWN_POLL_MS: u64 = 100;

/// Zenoh セッションのラッパー。publish / subscribe を抽象化。
pub struct ClientSession {
    inner: Session,
}

impl ClientSession {
    /// connect_config: 接続先（例: "tcp/127.0.0.1:7447"）。空ならデフォルト（scouting）。
    pub fn open(connect_config: &str) -> Result<Self, String> {
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
        let session = zenoh::open(config)
            .wait()
            .map_err(|e| format!("zenoh open failed: {e}"))?;
        Ok(Self { inner: session })
    }

    pub fn put(&self, key: &str, payload: &[u8]) -> Result<(), String> {
        let publisher = self
            .inner
            .declare_publisher(key)
            .wait()
            .map_err(|e| format!("publisher declare failed: {e}"))?;
        publisher
            .put(payload)
            .wait()
            .map_err(|e| format!("put failed: {e}"))?;
        Ok(())
    }

    pub fn put_drop(&self, key: &str, payload: &[u8]) -> Result<(), String> {
        let publisher = self
            .inner
            .declare_publisher(key)
            .congestion_control(CongestionControl::Drop)
            .wait()
            .map_err(|e| format!("publisher declare failed: {e}"))?;
        let _ = publisher.put(payload).wait();
        Ok(())
    }

    pub fn spawn_subscriber<F>(
        &self,
        key: &str,
        shutdown: std::sync::Arc<AtomicBool>,
        on_payload: F,
    ) -> thread::JoinHandle<()>
    where
        F: Fn(Vec<u8>) + Send + 'static,
    {
        let session = self.inner.clone();
        let key = key.to_string();
        thread::spawn(move || {
            if let Err(e) = run_subscriber(&session, &key, shutdown, on_payload) {
                log::error!("subscriber error: {e}");
            }
        })
    }
}

fn run_subscriber<F>(
    session: &Session,
    key_expr: &str,
    shutdown: std::sync::Arc<AtomicBool>,
    on_payload: F,
) -> Result<(), String>
where
    F: Fn(Vec<u8>) + Send + 'static,
{
    let subscriber = session
        .declare_subscriber(key_expr)
        .wait()
        .map_err(|e| format!("subscribe failed: {e}"))?;

    log::info!("[zenoh subscriber] subscribed to {key_expr}");

    while !shutdown.load(Ordering::SeqCst) {
        let recv_fut = subscriber.recv_async();
        let timeout = Delay::new(Duration::from_millis(SHUTDOWN_POLL_MS));

        match futures::executor::block_on(select(recv_fut, timeout)) {
            Either::Left((Ok(sample), _)) => {
                let payload = sample.payload().to_bytes();
                on_payload(payload.to_vec());
            }
            Either::Left((Err(e), _)) => {
                log::debug!("recv error: {e}");
            }
            Either::Right((_, _)) => {}
        }
    }
    Ok(())
}
