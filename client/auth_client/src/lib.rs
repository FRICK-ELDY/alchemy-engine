//! auth_client: alchemy-auth API クライアント
//!
//! クライアント ↔ auth の HTTPS 通信と、world-server の `POST /api/room_token`
//! （Bearer の access token から入室用 RoomToken を取る）を担う。
//! パスワードと access token は Zenoh には載せない。Zenoh に載るのは RoomToken だけ。
//!
//! # 実行モデル
//!
//! winit のイベントループ（同期）から使うため、各 API 呼び出しは
//! [`AuthTask`] としてワーカースレッドで実行し、UI 側は毎フレーム
//! [`AuthTask::try_take`] でポーリングする。

mod api;
mod error;
mod models;
mod task;
mod token_store;

pub use api::{
    default_base_url, default_engine_base_url, AuthClient, AUTH_URL_ENV, ENGINE_URL_ENV,
};
pub use error::AuthError;
pub use models::{FieldErrors, RegisterRequest, Session, UserInfo};
pub use task::AuthTask;
pub use token_store::TokenStore;
