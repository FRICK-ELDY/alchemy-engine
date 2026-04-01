//! トピック管理・共通処理

/// フレーム配信用キー
pub fn frame_key(room_id: &str) -> String {
    format!("game/room/{room_id}/frame")
}

/// 移動入力用キー
pub fn movement_key(room_id: &str) -> String {
    format!("game/room/{room_id}/input/movement")
}

/// アクション入力用キー
pub fn action_key(room_id: &str) -> String {
    format!("game/room/{room_id}/input/action")
}

/// クライアント情報用キー
pub fn client_info_key(room_id: &str) -> String {
    format!("contents/room/{room_id}/client/info")
}
