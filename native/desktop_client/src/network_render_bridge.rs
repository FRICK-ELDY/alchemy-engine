//! NetworkRenderBridge: Zenoh 経由でフレーム受信・入力送信
//!
//! クライアント exe 用。サーバーと分離された別プロセスで動作する。

use desktop_render::window::{KeyCode, KeyState, RenderBridge};
use desktop_render::RenderFrame;
use futures::future::{select, Either};
use futures_timer::Delay;
use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use zenoh::config::Config;
use zenoh::qos::CongestionControl;
use zenoh::{Session, Wait};

fn frame_key(room_id: &str) -> String {
    format!("game/room/{room_id}/frame")
}

fn movement_key(room_id: &str) -> String {
    format!("game/room/{room_id}/input/movement")
}

fn action_key(room_id: &str) -> String {
    format!("game/room/{room_id}/input/action")
}

/// WASD / 矢印キー → dx, dy
fn move_vector_from_keys(keys: &HashSet<KeyCode>) -> (f32, f32) {
    let dx = (keys.contains(&KeyCode::KeyD) || keys.contains(&KeyCode::ArrowRight)) as i32
        - (keys.contains(&KeyCode::KeyA) || keys.contains(&KeyCode::ArrowLeft)) as i32;
    let dy = (keys.contains(&KeyCode::KeyS) || keys.contains(&KeyCode::ArrowDown)) as i32
        - (keys.contains(&KeyCode::KeyW) || keys.contains(&KeyCode::ArrowUp)) as i32;
    (dx as f32, dy as f32)
}

pub struct NetworkRenderBridge {
    frame_buffer: Arc<Mutex<Option<RenderFrame>>>,
    keys_held: Arc<Mutex<HashSet<KeyCode>>>,
    session: Session,
    movement_key_expr: String,
    action_key_expr: String,
    #[allow(dead_code)]
    room_id: String,
    recv_handle: Option<thread::JoinHandle<()>>,
    shutdown: Arc<AtomicBool>,
}

impl NetworkRenderBridge {
    /// connect_config: Zenoh 接続先（例: "tcp/127.0.0.1:7447"）。空ならデフォルト（scouting）。
    /// 指定時は Config の connect.endpoints に設定する。
    pub fn new(connect_config: &str, room_id: &str) -> Result<Self, String> {
        let mut config = Config::default();
        if !connect_config.is_empty() {
            config
                .insert_json5(
                    "connect/endpoints",
                    format!(r#"["{}"]"#, connect_config).as_str(),
                )
                .map_err(|e| format!("zenoh connect config failed: {e}"))?;
        }
        let session = zenoh::open(config)
            .wait()
            .map_err(|e| format!("zenoh open failed: {e}"))?;

        let frame_buffer: Arc<Mutex<Option<RenderFrame>>> = Arc::new(Mutex::new(None));
        let keys_held = Arc::new(Mutex::new(HashSet::new()));
        let shutdown = Arc::new(AtomicBool::new(false));

        let sub_key = frame_key(room_id);
        let buf_clone = Arc::clone(&frame_buffer);
        let shutdown_clone = Arc::clone(&shutdown);
        let session_clone = session.clone();

        let recv_handle = thread::spawn(move || {
            if let Err(e) = run_receiver(&session_clone, &sub_key, buf_clone, shutdown_clone) {
                log::error!("frame receiver error: {e}");
            }
        });

        Ok(Self {
            frame_buffer,
            keys_held,
            session,
            movement_key_expr: movement_key(room_id),
            action_key_expr: action_key(room_id),
            room_id: room_id.to_string(),
            recv_handle: Some(recv_handle),
            shutdown,
        })
    }

    fn publish_movement(&self, dx: f32, dy: f32) {
        #[derive(serde::Serialize)]
        struct MovementPayload {
            dx: f64,
            dy: f64,
        }
        let payload = match rmp_serde::to_vec(&MovementPayload {
            dx: dx as f64,
            dy: dy as f64,
        }) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("movement serialize error: {e}");
                return;
            }
        };
        let publisher = match self
            .session
            .declare_publisher(&self.movement_key_expr)
            .congestion_control(CongestionControl::Drop)
            .wait()
        {
            Ok(p) => p,
            Err(e) => {
                log::warn!("movement publisher declare failed: {e}");
                return;
            }
        };
        let _ = publisher.put(payload).wait();
    }

    fn publish_action(&self, name: &str) {
        #[derive(serde::Serialize)]
        struct ActionPayload<'a> {
            name: &'a str,
            payload: std::collections::HashMap<String, String>,
        }
        let payload = match rmp_serde::to_vec(&ActionPayload {
            name,
            payload: std::collections::HashMap::new(),
        }) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("action serialize error: {e}");
                return;
            }
        };
        let publisher = match self.session.declare_publisher(&self.action_key_expr).wait() {
            Ok(p) => p,
            Err(e) => {
                log::warn!("action publisher declare failed: {e}");
                return;
            }
        };
        let _ = publisher.put(payload).wait();
    }
}

impl Drop for NetworkRenderBridge {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::SeqCst);
        if let Some(h) = self.recv_handle.take() {
            let _ = h.join();
        }
    }
}

/// 100ms ごとに shutdown を確認するためのポーリング間隔
const SHUTDOWN_POLL_MS: u64 = 100;

fn run_receiver(
    session: &Session,
    key_expr: &str,
    frame_buffer: Arc<Mutex<Option<RenderFrame>>>,
    shutdown: Arc<AtomicBool>,
) -> Result<(), String> {
    let subscriber = session
        .declare_subscriber(key_expr)
        .wait()
        .map_err(|e| format!("subscribe failed: {e}"))?;

    log::info!("[frame receiver] subscribed to {key_expr}, waiting for frames...");

    let mut frame_count: u64 = 0;
    let mut last_wait_log = std::time::Instant::now();
    while !shutdown.load(Ordering::SeqCst) {
        let recv_fut = subscriber.recv_async();
        let timeout = Delay::new(Duration::from_millis(SHUTDOWN_POLL_MS));

        match futures::executor::block_on(select(recv_fut, timeout)) {
            Either::Left((Ok(sample), _)) => {
                let payload = sample.payload();
                let len = payload.to_bytes().len();
                if frame_count == 0 {
                    log::info!("[frame receiver] first raw sample received size={len} bytes");
                }
                match crate::msgpack_decode::decode_render_frame(payload.to_bytes().as_ref()) {
                    Ok(frame) => {
                        if let Ok(mut guard) = frame_buffer.lock() {
                            *guard = Some(frame);
                        }
                        frame_count += 1;
                        if frame_count == 1 {
                            log::info!("[frame receiver] first frame received and decoded");
                        }
                    }
                    Err(e) => {
                        log::warn!("[frame receiver] decode error: {e} (payload size={len})");
                    }
                }
            }
            Either::Left((Err(e), _)) => {
                log::debug!("recv error: {e}");
            }
            Either::Right((_, _)) => {
                // タイムアウト: shutdown を再確認してループ継続
                if frame_count == 0 && last_wait_log.elapsed().as_secs() >= 5 {
                    log::warn!(
                        "[frame receiver] still waiting for frames after 5s (key={key_expr})"
                    );
                    last_wait_log = std::time::Instant::now();
                }
            }
        }
    }
    Ok(())
}

impl RenderBridge for NetworkRenderBridge {
    fn next_frame(&self) -> RenderFrame {
        let (dx, dy) = {
            let keys = self.keys_held.lock().unwrap();
            move_vector_from_keys(&keys)
        };
        self.publish_movement(dx, dy);

        if let Ok(mut guard) = self.frame_buffer.lock() {
            if let Some(frame) = guard.take() {
                return frame;
            }
        }
        RenderFrame::default()
    }

    fn on_ui_action(&self, action: String) {
        self.publish_action(&action);
    }

    fn on_raw_key(&self, key: KeyCode, state: KeyState) {
        let mut keys = self.keys_held.lock().unwrap();
        match state {
            KeyState::Pressed => {
                keys.insert(key);
            }
            KeyState::Released => {
                keys.remove(&key);
            }
        }
    }

    fn on_raw_mouse_motion(&self, _dx: f32, _dy: f32) {
        // マウスデルタ用スタブ。将来のマウス入力拡張（例: 視点操作）用に _dx, _dy を利用する。
    }

    fn on_focus_lost(&self) {
        self.keys_held.lock().unwrap().clear();
    }
}
