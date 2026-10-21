//! auth API のリクエスト/レスポンス型（auth/README.md の JSON 仕様に対応）。

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// フィールド名 → エラーメッセージ一覧（422 レスポンスの `errors.fields`）。
pub type FieldErrors = BTreeMap<String, Vec<String>>;

/// `POST /api/v1/auth/register` のリクエストボディ。
///
/// `repeat_email` / `repeat_password` はクライアント検証のみで API には送らない。
#[derive(Clone, Debug, Serialize)]
pub struct RegisterRequest {
    pub username: String,
    pub email: String,
    pub password: String,
    /// ISO 8601 (YYYY-MM-DD)
    pub birthday: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub promo_code: Option<String>,
    pub tos_agreed: bool,
    pub remember_me: bool,
}

/// register / login / refresh 共通の成功レスポンス。
#[derive(Clone, Debug, Deserialize)]
pub struct Session {
    pub access_token: String,
    pub token_type: String,
    pub expires_in: u64,
    /// remember_me: true のときのみ返る opaque トークン。
    #[serde(default)]
    pub refresh_token: Option<String>,
    pub user: UserInfo,
}

#[derive(Clone, Debug, Deserialize)]
pub struct UserInfo {
    pub user_id: String,
    pub username: String,
    pub email: String,
}

/// エラーレスポンス `{"errors": {"detail": ..., "fields": {...}}}` の内側。
#[derive(Clone, Debug, Default, Deserialize)]
pub(crate) struct ApiErrorBody {
    #[serde(default)]
    pub detail: Option<String>,
    #[serde(default)]
    pub fields: FieldErrors,
}

#[derive(Clone, Debug, Deserialize)]
pub(crate) struct ApiErrorEnvelope {
    #[serde(default)]
    pub errors: ApiErrorBody,
}
