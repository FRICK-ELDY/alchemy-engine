//! game_audio: SuperCollider風コマンド駆動オーディオスレッド
//! Elixir（指揮者）が非同期コマンドを発行し、専用スレッドがDSP処理を行う。

pub mod asset;
mod audio;

pub use asset::{AssetId, AssetLoader};
pub use audio::{start_audio_thread, AudioCommand, AudioCommandSender, AudioManager};
