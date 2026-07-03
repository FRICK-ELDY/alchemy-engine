//! auth_client: alchemy-auth API クライアント
//!
//! クライアント ↔ auth の直接 HTTPS 通信のみを担う。資格情報（パスワード・
//! トークン）はこのクレートと呼び出し元（system_ui）だけを通り、
//! Zenoh / engine サーバには一切流さない（login-register-ui-plan.md 2.1）。
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

pub use api::{default_base_url, AuthClient, AUTH_URL_ENV};
pub use error::AuthError;
pub use models::{FieldErrors, RegisterRequest, Session, UserInfo};
pub use task::AuthTask;
pub use token_store::TokenStore;
