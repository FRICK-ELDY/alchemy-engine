//! NetworkRenderBridge: Zenoh 経由でフレーム受信・入力送信
//!
//! クライアント exe 用。サーバーと分離された別プロセスで動作する。
//! Zenoh 通信は client::zenoh を経由する（zenoh クレートへの直接依存なし）。

use client::zenoh::ClientSession;
use desktop_render::window::{KeyCode, KeyState, RenderBridge};
use desktop_render::RenderFrame;
use network::{action_key, client_info_key, frame_key, movement_key};
use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

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
    session: ClientSession,
    movement_key_expr: String,
    action_key_expr: String,
    #[allow(dead_code)]
    room_id: String,
    recv_handle: Option<thread::JoinHandle<()>>,
    shutdown: Arc<AtomicBool>,
}

impl NetworkRenderBridge {
    /// connect_config: Zenoh 接続先（例: "tcp/127.0.0.1:7447"）。空ならデフォルト（scouting）。
    pub fn new(connect_config: &str, room_id: &str) -> Result<Self, String> {
        let session = ClientSession::open(connect_config)?;

        let frame_buffer: Arc<Mutex<Option<RenderFrame>>> = Arc::new(Mutex::new(None));
        let keys_held = Arc::new(Mutex::new(HashSet::new()));
        let shutdown = Arc::new(AtomicBool::new(false));

        let sub_key = frame_key(room_id);
        let buf_clone = Arc::clone(&frame_buffer);
        let shutdown_clone = Arc::clone(&shutdown);
        let frame_count = Arc::new(AtomicU64::new(0));

        let recv_handle = {
            let frame_count_clone = Arc::clone(&frame_count);
            session.spawn_subscriber(&sub_key, shutdown_clone, move |bytes| {
                match crate::msgpack_decode::decode_render_frame(&bytes) {
                    Ok(frame) => {
                        let prev = frame_count_clone.fetch_add(1, Ordering::Relaxed);
                        if prev == 0 {
                            log::info!("[frame receiver] first frame received and decoded");
                        }
                        if let Ok(mut guard) = buf_clone.lock() {
                            *guard = Some(frame);
                        }
                    }
                    Err(e) => {
                        log::warn!(
                            "[frame receiver] decode error: {e} (payload size={})",
                            bytes.len()
                        );
                    }
                }
            })
        };

        let bridge = Self {
            frame_buffer,
            keys_held,
            session,
            movement_key_expr: movement_key(room_id),
            action_key_expr: action_key(room_id),
            room_id: room_id.to_string(),
            recv_handle: Some(recv_handle),
            shutdown,
        };
        bridge.publish_client_info(room_id);
        Ok(bridge)
    }

    fn publish_client_info(&self, room_id: &str) {
        let info = client::info::ClientInfo::current();
        let payload = match rmp_serde::to_vec(&info) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("client info serialize error: {e}");
                return;
            }
        };
        let key = client_info_key(room_id);
        if let Err(e) = self.session.put(&key, &payload) {
            log::warn!("client info publish error: {e}");
        } else {
            log::info!("[client info] published to {key}");
        }
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
        if let Err(e) = self.session.put_drop(&self.movement_key_expr, &payload) {
            log::warn!("movement publish failed: {e}");
        }
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
        if let Err(e) = self.session.put(&self.action_key_expr, &payload) {
            log::warn!("action publish failed: {e}");
        }
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
