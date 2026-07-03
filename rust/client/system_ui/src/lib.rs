//! system_ui: クライアント所有のシステムUI（The Voice of the Client）
//!
//! ESC で開閉するシステムメニュー（ログイン/登録・Quit・将来の設定）を提供する。
//!
//! # 責務境界（login-register-ui-plan.md 1.3）
//!
//! - ゲーム内 UI（HUD 等）は Contents（Elixir）が Canvas DSL で定義し、
//!   `render::renderer::ui` が描画する。
//! - システム UI（本クレート）はクライアントが所有し、サーバを経由しない。
//!   資格情報は egui ローカルに保持し、Zenoh には一切流さない。
//!
//! ホスト（window::desktop_loop）は以下だけを行う:
//! - ESC 押下時に [`SystemUi::handle_escape`] を呼ぶ（サーバへは送らない）
//! - 毎フレーム [`SystemUi::render`] を egui overlay として呼び、
//!   返された [`SystemUiEvent`] を処理する（Quit → イベントループ終了）
//! - [`SystemUi::is_open`] が真の間はゲーム入力を遮断しカーソルを解放する

pub use egui;

mod menu;
mod state;

pub use state::{
    item_visible, MenuEnvironment, MenuItem, Screen, SessionState, SystemUi, SystemUiEvent,
};
