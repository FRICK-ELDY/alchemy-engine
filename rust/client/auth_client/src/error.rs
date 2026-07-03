//! auth API 呼び出しのエラー型。

use crate::models::FieldErrors;
use std::fmt;

/// auth API 呼び出しの失敗。UI はこれをそのまま表示に使える。
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AuthError {
    /// ベース URL が不正（localhost 以外の http など）。起動設定の誤り。
    InvalidBaseUrl(String),
    /// 401: 資格情報が誤っている（ユーザー列挙防止のため単一メッセージ）。
    InvalidCredentials(String),
    /// 422: サーバサイドバリデーション失敗。フィールド別メッセージを持つ。
    Validation { detail: String, fields: FieldErrors },
    /// 接続不可・タイムアウト等のネットワークエラー。
    Network(String),
    /// 上記以外の HTTP エラー（500 等）。
    Server { status: u16, detail: String },
}

impl fmt::Display for AuthError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AuthError::InvalidBaseUrl(msg) => write!(f, "invalid auth URL: {msg}"),
            AuthError::InvalidCredentials(detail) => write!(f, "{detail}"),
            AuthError::Validation { detail, .. } => write!(f, "{detail}"),
            AuthError::Network(msg) => write!(f, "network error: {msg}"),
            AuthError::Server { status, detail } => write!(f, "server error ({status}): {detail}"),
        }
    }
}

impl std::error::Error for AuthError {}
