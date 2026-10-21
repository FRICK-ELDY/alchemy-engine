//! NetworkRenderBridge: Zenoh 経由でフレーム受信・入力送信
//!
//! クライアント exe 用。サーバーと分離された別プロセスで動作する。
//! Zenoh 通信は platform/desktop.rs の ClientSession を経由する。
//! 受信スナップショットは `shared::SnapshotInterpolator` で直近 2 枚を保持し、
//! ~100ms の描画遅延バッファ上で座標を線形補間して 60fps 描画へ渡す。

use crate::room_envelope::wrap_room_payload;
use crate::{action_key, client_info_key, frame_key, movement_key, ClientInfo, ClientSession};
use audio::AudioCommandSender;
use render::window::{KeyCode, KeyState, RenderBridge};
use render::RenderFrame;
use shared::SnapshotInterpolator;
use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

/// この時間フレームを受信しなければ切断（未接続）とみなす。
const CONNECTED_TIMEOUT: Duration = Duration::from_secs(3);

/// RoomToken のサーバ側寿命（300 秒）より前に取り直す。
const ROOM_TOKEN_REFRESH: Duration = Duration::from_secs(240);

/// サーバが署名時に埋め込む最大寿命。これを過ぎたトークンは封筒に載せない。
const ROOM_TOKEN_TTL: Duration = Duration::from_secs(300);

/// 取得失敗のあと、次の `POST /api/room_token` まで空ける。
const ROOM_TOKEN_RETRY: Duration = Duration::from_secs(5);

/// access token と room_id から RoomToken を取る。
pub type RoomTokenFetch = Arc<dyn Fn(&str, &str) -> Result<String, String> + Send + Sync>;

struct RoomAuthState {
    access_token: Option<String>,
    room_token: Option<Arc<str>>,
    issued_at: Option<Instant>,
    /// この時刻より前は取得しない。失敗直後の毎フレーム再送を止める。
    retry_not_before: Option<Instant>,
    fetch: Option<RoomTokenFetch>,
    room_id: String,
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
    /// 直近 2 スナップショット + 描画遅延バッファによる補間器。
    snapshots: Arc<Mutex<SnapshotInterpolator>>,
    /// 新規フレーム受信時に `audio_cues` を再生する。補間サンプルでは再再生しない。
    audio_tx: Option<AudioCommandSender>,
    keys_held: Arc<Mutex<HashSet<KeyCode>>>,
    session: ClientSession,
    movement_key_expr: String,
    action_key_expr: String,
    #[allow(dead_code)]
    room_id: String,
    recv_handle: Option<thread::JoinHandle<()>>,
    shutdown: Arc<AtomicBool>,
    /// 最後にフレームを受信した時刻（`creation_time` からの経過ミリ秒。未受信は `u64::MAX`）。
    /// `CONNECTED_TIMEOUT` 以内なら接続中とみなす（単調カウンタだと切断後も
    /// 接続扱いになるため時刻ベースで判定する）。受信は高頻度なため、
    /// ロック競合を避けて AtomicU64 でロックフリーに管理する。
    last_frame_elapsed_ms: Arc<AtomicU64>,
    creation_time: Instant,
    room_auth: Arc<Mutex<RoomAuthState>>,
    room_token_refreshing: Arc<AtomicBool>,
    client_info_publish: Arc<Mutex<ClientInfoPublish>>,
}

/// `sent == None` は未送信。`Some(None)` は未ログインの生送信。`Some(Some(token))` はその RoomToken で送信済み。
struct ClientInfoPublish {
    sent: Option<Option<Arc<str>>>,
    /// put 失敗後、同じトークンではこの時刻まで再送しない。
    retry_not_before: Option<(Option<Arc<str>>, Instant)>,
}

impl NetworkRenderBridge {
    /// connect_config: Zenoh 接続先（例: "tcp/127.0.0.1:7447"）。空ならデフォルト（scouting）。
    pub fn new(connect_config: &str, room_id: &str) -> Result<Self, String> {
        Self::new_with_audio(connect_config, room_id, None)
    }

    /// `audio_tx` を渡すと、Zenoh で受信した新フレームの `audio_cues` をオーディオスレッドへ送る。
    pub fn new_with_audio(
        connect_config: &str,
        room_id: &str,
        audio_tx: Option<AudioCommandSender>,
    ) -> Result<Self, String> {
        Self::new_with_room_auth(connect_config, room_id, audio_tx, None)
    }

    /// `fetch` があると、`set_bearer_for_room` で渡した access token から RoomToken を取り、
    /// movement / action / client_info を封筒に載せる。
    pub fn new_with_room_auth(
        connect_config: &str,
        room_id: &str,
        audio_tx: Option<AudioCommandSender>,
        fetch: Option<RoomTokenFetch>,
    ) -> Result<Self, String> {
        let session = ClientSession::open(connect_config)?;

        let snapshots: Arc<Mutex<SnapshotInterpolator>> =
            Arc::new(Mutex::new(SnapshotInterpolator::new()));
        let keys_held = Arc::new(Mutex::new(HashSet::new()));
        let shutdown = Arc::new(AtomicBool::new(false));

        let sub_key = frame_key(room_id);
        let snapshots_clone = Arc::clone(&snapshots);
        let shutdown_clone = Arc::clone(&shutdown);
        let frame_count = Arc::new(AtomicU64::new(0));
        let creation_time = Instant::now();
        let last_frame_elapsed_ms = Arc::new(AtomicU64::new(u64::MAX));

        let recv_handle = {
            let frame_count_clone = Arc::clone(&frame_count);
            let last_frame_elapsed_ms_clone = Arc::clone(&last_frame_elapsed_ms);
            session.spawn_subscriber(&sub_key, shutdown_clone, move |bytes| {
                match decode_render_frame_from_zenoh(&bytes) {
                    Ok(frame) => {
                        let prev = frame_count_clone.fetch_add(1, Ordering::Relaxed);
                        if prev == 0 {
                            log::info!("[frame receiver] first frame received and decoded");
                        }
                        let received_at = Instant::now();
                        let elapsed = creation_time.elapsed().as_millis() as u64;
                        last_frame_elapsed_ms_clone.store(elapsed, Ordering::Relaxed);
                        match snapshots_clone.lock() {
                            Ok(mut guard) => guard.push(frame, received_at),
                            Err(e) => {
                                log::warn!("[frame receiver] snapshots lock failed (poisoned): {e}")
                            }
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
            snapshots,
            audio_tx,
            keys_held,
            session,
            movement_key_expr: movement_key(room_id),
            action_key_expr: action_key(room_id),
            room_id: room_id.to_string(),
            recv_handle: Some(recv_handle),
            shutdown,
            last_frame_elapsed_ms,
            creation_time,
            room_auth: Arc::new(Mutex::new(RoomAuthState {
                access_token: None,
                room_token: None,
                issued_at: None,
                retry_not_before: None,
                fetch,
                room_id: room_id.to_string(),
            })),
            room_token_refreshing: Arc::new(AtomicBool::new(false)),
            client_info_publish: Arc::new(Mutex::new(ClientInfoPublish {
                sent: None,
                retry_not_before: None,
            })),
        };
        bridge.publish_client_info_if_token_changed();
        Ok(bridge)
    }

    /// ログイン中で、まだ有効な RoomToken が無いときは `None`（生の protobuf は送らない）。
    /// 未ログイン（access token なし）のときだけ生の protobuf を返す。
    fn seal(&self, protobuf: Vec<u8>) -> Option<(Vec<u8>, Option<Arc<str>>)> {
        let guard = self.room_auth.lock().ok()?;
        if guard.access_token.is_none() {
            return Some((protobuf, None));
        }
        let token = usable_room_token(&guard)?;
        match wrap_room_payload(&token, &protobuf) {
            Ok(wrapped) => Some((wrapped, Some(token))),
            Err(e) => {
                log::warn!("room token envelope skipped: {e}");
                None
            }
        }
    }

    /// put に成功したとき、その送信に使った RoomToken（未ログインの生送信は `None`）を返す。
    fn publish_client_info(&self) -> Option<Option<Arc<str>>> {
        let room_id = match self.room_auth.lock() {
            Ok(guard) => guard.room_id.clone(),
            Err(e) => {
                log::warn!("client info skipped, room auth lock poisoned: {e}");
                return None;
            }
        };
        let info = ClientInfo::current();
        let (payload, token) = match crate::protobuf_codec::encode_client_info(&info) {
            Ok(p) => self.seal(p)?,
            Err(e) => {
                log::warn!("client info serialize error: {e}");
                return None;
            }
        };
        let key = client_info_key(&room_id);
        match self.session.put(&key, &payload) {
            Ok(()) => {
                log::info!("[client info] published to {key}");
                Some(token)
            }
            Err(e) => {
                log::warn!("client info publish error: {e}");
                None
            }
        }
    }

    fn publish_client_info_if_token_changed(&self) {
        let current = match self.room_auth.lock() {
            Ok(guard) => {
                if guard.access_token.is_some() {
                    match usable_room_token(&guard) {
                        Some(token) => Some(token),
                        None => return,
                    }
                } else {
                    None
                }
            }
            Err(e) => {
                log::warn!("client info generation lock poisoned: {e}");
                return;
            }
        };
        let should_send = match self.client_info_publish.lock() {
            Ok(state) => {
                if state.sent.as_ref() == Some(&current) {
                    false
                } else if let Some((failed_for, at)) = &state.retry_not_before {
                    failed_for != &current || Instant::now() >= *at
                } else {
                    true
                }
            }
            Err(e) => {
                log::warn!("client info generation lock poisoned: {e}");
                return;
            }
        };
        if !should_send {
            return;
        }
        match self.publish_client_info() {
            Some(sent_token) => {
                if let Ok(mut state) = self.client_info_publish.lock() {
                    state.sent = Some(sent_token);
                    state.retry_not_before = None;
                }
            }
            None => {
                if let Ok(mut state) = self.client_info_publish.lock() {
                    state.retry_not_before = Some((current, Instant::now() + ROOM_TOKEN_RETRY));
                }
            }
        }
    }

    fn publish_movement(&self, dx: f32, dy: f32) {
        let payload = match crate::protobuf_codec::encode_movement(dx, dy) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("movement serialize error: {e}");
                return;
            }
        };
        let Some((payload, _)) = self.seal(payload) else {
            return;
        };
        if let Err(e) = self.session.put_drop(&self.movement_key_expr, &payload) {
            log::warn!("[input:client] movement publish failed: {e}");
        }
    }

    fn publish_action(&self, name: &str) {
        let payload = match crate::protobuf_codec::encode_action(name) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("action serialize error: {e}");
                return;
            }
        };
        let Some((payload, _)) = self.seal(payload) else {
            return;
        };
        if let Err(e) = self.session.put(&self.action_key_expr, &payload) {
            log::warn!("action publish failed: {e}");
        }
    }

    fn ensure_room_token(&self) {
        let needs_fetch = match self.room_auth.lock() {
            Ok(guard) => {
                let due = guard
                    .issued_at
                    .is_none_or(|issued| issued.elapsed() >= ROOM_TOKEN_REFRESH);
                let retry_open = guard.retry_not_before.is_none_or(|at| Instant::now() >= at);
                guard.access_token.is_some() && guard.fetch.is_some() && due && retry_open
            }
            Err(e) => {
                log::warn!("room auth lock poisoned: {e}");
                false
            }
        };
        if !needs_fetch {
            return;
        }
        if self
            .room_token_refreshing
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
            .is_err()
        {
            return;
        }

        let auth = Arc::clone(&self.room_auth);
        let flag = Arc::clone(&self.room_token_refreshing);
        thread::spawn(move || {
            let _guard = RefreshFlagGuard {
                flag,
                auth: Arc::clone(&auth),
            };
            let job = match auth.lock() {
                Ok(guard) => match (guard.fetch.clone(), guard.access_token.clone()) {
                    (Some(fetch), Some(access)) => Some((fetch, access, guard.room_id.clone())),
                    _ => None,
                },
                Err(e) => {
                    log::warn!("room token refresh lock poisoned: {e}");
                    None
                }
            };

            if let Some((fetch, access, room_id)) = job {
                let result = fetch(&access, &room_id);
                match auth.lock() {
                    Ok(mut guard) => {
                        if guard.access_token.as_ref() == Some(&access) {
                            match result {
                                Ok(token) => {
                                    guard.room_token = Some(Arc::from(token));
                                    guard.issued_at = Some(Instant::now());
                                    guard.retry_not_before = None;
                                }
                                Err(e) => {
                                    log::warn!("room token fetch failed: {e}");
                                    guard.retry_not_before =
                                        Some(Instant::now() + ROOM_TOKEN_RETRY);
                                    if guard
                                        .issued_at
                                        .is_some_and(|issued| issued.elapsed() >= ROOM_TOKEN_TTL)
                                    {
                                        guard.room_token = None;
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => log::warn!("room token store lock poisoned: {e}"),
                }
            }
        });
    }
}

/// 取得スレッドがパニックしてもフラグを戻し、直後の再取得を止める。
struct RefreshFlagGuard {
    flag: Arc<AtomicBool>,
    auth: Arc<Mutex<RoomAuthState>>,
}

impl Drop for RefreshFlagGuard {
    fn drop(&mut self) {
        if std::thread::panicking() {
            log::warn!("room token fetch panicked");
            if let Ok(mut guard) = self.auth.lock() {
                guard.retry_not_before = Some(Instant::now() + ROOM_TOKEN_RETRY);
            }
        }
        self.flag.store(false, Ordering::Release);
    }
}

fn usable_room_token(guard: &RoomAuthState) -> Option<Arc<str>> {
    let issued = guard.issued_at?;
    if issued.elapsed() >= ROOM_TOKEN_TTL {
        return None;
    }
    guard.room_token.clone()
}

fn decode_render_frame_from_zenoh(
    bytes: &[u8],
) -> Result<RenderFrame, Box<dyn std::error::Error + Send + Sync>> {
    crate::protobuf_render_frame::decode_pb_render_frame(bytes).map_err(|e| e.into())
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
        let (dx, dy) = match self.keys_held.lock() {
            Ok(keys) => move_vector_from_keys(&keys),
            Err(e) => {
                log::warn!("[network_render_bridge] keys_held lock failed (poisoned): {e}");
                (0.0, 0.0)
            }
        };
        self.ensure_room_token();
        self.publish_client_info_if_token_changed();
        self.publish_movement(dx, dy);

        let now = Instant::now();
        match self.snapshots.lock() {
            Ok(mut guard) => {
                if let Some(ref tx) = self.audio_tx {
                    for url in guard.take_pending_audio() {
                        tx.play_se_from_relative_path(url);
                    }
                } else {
                    // オーディオ未接続でもキューを捨て、次回に溜めない
                    let _ = guard.take_pending_audio();
                }
                guard.sample(now).unwrap_or_default()
            }
            Err(e) => {
                log::warn!("[network_render_bridge] snapshots lock failed (poisoned): {e}");
                RenderFrame::default()
            }
        }
    }

    fn on_ui_action(&self, action: String) {
        self.publish_action(&action);
    }

    fn on_raw_key(&self, key: KeyCode, state: KeyState) {
        let Ok(mut keys) = self.keys_held.lock() else {
            log::warn!("[network_render_bridge] keys_held lock failed (poisoned) in on_raw_key");
            return;
        };
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
        if let Ok(mut keys) = self.keys_held.lock() {
            keys.clear();
        } else {
            log::warn!("[network_render_bridge] keys_held lock failed (poisoned) in on_focus_lost");
        }
    }

    fn set_bearer_for_room(&self, access_token: Option<&str>) {
        let changed = match self.room_auth.lock() {
            Ok(mut guard) => {
                if guard.access_token.as_deref() == access_token {
                    false
                } else {
                    guard.access_token = access_token.map(str::to_string);
                    guard.room_token = None;
                    guard.issued_at = None;
                    guard.retry_not_before = None;
                    true
                }
            }
            Err(e) => {
                log::warn!("room auth lock poisoned: {e}");
                false
            }
        };
        if changed {
            self.ensure_room_token();
        }
    }

    fn is_connected(&self) -> bool {
        let last = self.last_frame_elapsed_ms.load(Ordering::Relaxed);
        if last == u64::MAX {
            return false;
        }
        let current = self.creation_time.elapsed().as_millis() as u64;
        current.saturating_sub(last) < CONNECTED_TIMEOUT.as_millis() as u64
    }
}
