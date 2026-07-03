//! auth API 呼び出し（同期）。UI からは `*_async` 経由で使う。

use crate::error::AuthError;
use crate::models::{ApiErrorEnvelope, RegisterRequest, Session, UserInfo};
use crate::task::AuthTask;
use std::time::Duration;

/// auth のベース URL を指定する環境変数。
pub const AUTH_URL_ENV: &str = "ALCHEMY_AUTH_URL";

/// 未指定時の既定 URL（ローカル開発用 alchemy-auth）。
pub fn default_base_url() -> String {
    "http://localhost:4002".to_string()
}

const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

/// alchemy-auth API クライアント。
///
/// `Clone` は内部接続プールを共有する（reqwest::blocking::Client と同じ意味論）。
#[derive(Clone)]
pub struct AuthClient {
    base_url: String,
    http: reqwest::blocking::Client,
}

impl AuthClient {
    /// ベース URL を検証してクライアントを作る。
    ///
    /// 本番は HTTPS 必須。`http` は localhost 系ホストのみ許可する
    /// （login-register-ui-plan.md 2.2）。
    pub fn new(base_url: &str) -> Result<Self, AuthError> {
        let url = reqwest::Url::parse(base_url)
            .map_err(|e| AuthError::InvalidBaseUrl(format!("{base_url}: {e}")))?;

        match url.scheme() {
            "https" => {}
            "http" => {
                let host = url.host_str().unwrap_or("");
                if !is_localhost(host) {
                    return Err(AuthError::InvalidBaseUrl(format!(
                        "http is only allowed for localhost, got {base_url}"
                    )));
                }
            }
            other => {
                return Err(AuthError::InvalidBaseUrl(format!(
                    "unsupported scheme {other} in {base_url}"
                )));
            }
        }

        let http = reqwest::blocking::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            // リダイレクト追跡による https → http ダウングレードでスキーム検証が
            // バイパスされるのを防ぐ。auth API はリダイレクトを使わない
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|e| AuthError::Network(e.to_string()))?;

        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            http,
        })
    }

    /// `ALCHEMY_AUTH_URL`（未設定なら `http://localhost:4002`）から作る。
    pub fn from_env() -> Result<Self, AuthError> {
        let base_url = std::env::var(AUTH_URL_ENV).unwrap_or_else(|_| default_base_url());
        Self::new(&base_url)
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    /// `POST /api/v1/auth/login`
    pub fn login(
        &self,
        identifier: &str,
        password: &str,
        remember_me: bool,
    ) -> Result<Session, AuthError> {
        let body = serde_json::json!({
            "identifier": identifier,
            "password": password,
            "remember_me": remember_me,
        });
        self.post_json("/api/v1/auth/login", &body)
    }

    /// `POST /api/v1/auth/register`（成功時は login と同形式でトークンが返る）
    pub fn register(&self, request: &RegisterRequest) -> Result<Session, AuthError> {
        self.post_json("/api/v1/auth/register", request)
    }

    /// `POST /api/v1/auth/refresh`
    pub fn refresh(&self, refresh_token: &str) -> Result<Session, AuthError> {
        let body = serde_json::json!({ "refresh_token": refresh_token });
        self.post_json("/api/v1/auth/refresh", &body)
    }

    /// `POST /api/v1/auth/logout`（access token 必須、refresh token があれば revoke）
    pub fn logout(&self, access_token: &str, refresh_token: Option<&str>) -> Result<(), AuthError> {
        let body = match refresh_token {
            Some(token) => serde_json::json!({ "refresh_token": token }),
            None => serde_json::json!({}),
        };
        let response = self
            .http
            .post(format!("{}/api/v1/auth/logout", self.base_url))
            .bearer_auth(access_token)
            .json(&body)
            .send()
            .map_err(network_error)?;

        let status = response.status();
        if status.is_success() {
            Ok(())
        } else {
            Err(error_from_response(response))
        }
    }

    /// `GET /api/v1/auth/me`
    pub fn me(&self, access_token: &str) -> Result<UserInfo, AuthError> {
        let response = self
            .http
            .get(format!("{}/api/v1/auth/me", self.base_url))
            .bearer_auth(access_token)
            .send()
            .map_err(network_error)?;
        parse_json_response(response)
    }

    /// ログインをワーカースレッドで実行する（UI から毎フレームポーリング）。
    pub fn login_async(
        &self,
        identifier: String,
        password: String,
        remember_me: bool,
    ) -> AuthTask<Session> {
        let client = self.clone();
        AuthTask::spawn(move || client.login(&identifier, &password, remember_me))
    }

    /// 登録をワーカースレッドで実行する。
    pub fn register_async(&self, request: RegisterRequest) -> AuthTask<Session> {
        let client = self.clone();
        AuthTask::spawn(move || client.register(&request))
    }

    /// リフレッシュをワーカースレッドで実行する（Phase 4 の自動ログイン用）。
    pub fn refresh_async(&self, refresh_token: String) -> AuthTask<Session> {
        let client = self.clone();
        AuthTask::spawn(move || client.refresh(&refresh_token))
    }

    fn post_json<B: serde::Serialize, T: serde::de::DeserializeOwned>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T, AuthError> {
        let response = self
            .http
            .post(format!("{}{}", self.base_url, path))
            .json(body)
            .send()
            .map_err(network_error)?;
        parse_json_response(response)
    }
}

fn is_localhost(host: &str) -> bool {
    matches!(host, "localhost" | "127.0.0.1" | "[::1]" | "::1")
}

fn network_error(e: reqwest::Error) -> AuthError {
    if e.is_timeout() {
        AuthError::Network("request timed out".to_string())
    } else if e.is_connect() {
        AuthError::Network("could not connect to auth service".to_string())
    } else {
        AuthError::Network(e.to_string())
    }
}

fn parse_json_response<T: serde::de::DeserializeOwned>(
    response: reqwest::blocking::Response,
) -> Result<T, AuthError> {
    let status = response.status();
    if status.is_success() {
        response.json::<T>().map_err(|e| AuthError::Server {
            status: status.as_u16(),
            detail: format!("invalid response body: {e}"),
        })
    } else {
        Err(error_from_response(response))
    }
}

fn error_from_response(response: reqwest::blocking::Response) -> AuthError {
    let status = response.status().as_u16();
    let body: ApiErrorEnvelope = response.json().unwrap_or_else(|_| ApiErrorEnvelope {
        errors: Default::default(),
    });
    let detail = body
        .errors
        .detail
        .unwrap_or_else(|| "request failed".to_string());

    match status {
        401 => AuthError::InvalidCredentials(detail),
        422 => AuthError::Validation {
            detail,
            fields: body.errors.fields,
        },
        _ => AuthError::Server { status, detail },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn https_url_is_accepted() {
        assert!(AuthClient::new("https://auth.example.com").is_ok());
    }

    #[test]
    fn http_localhost_is_accepted() {
        assert!(AuthClient::new("http://localhost:4002").is_ok());
        assert!(AuthClient::new("http://127.0.0.1:4002").is_ok());
    }

    #[test]
    fn http_remote_is_rejected() {
        assert!(matches!(
            AuthClient::new("http://auth.example.com"),
            Err(AuthError::InvalidBaseUrl(_))
        ));
    }

    #[test]
    fn invalid_scheme_is_rejected() {
        assert!(matches!(
            AuthClient::new("ftp://localhost"),
            Err(AuthError::InvalidBaseUrl(_))
        ));
    }

    #[test]
    fn trailing_slash_is_trimmed() {
        let client = AuthClient::new("http://localhost:4002/").unwrap();
        assert_eq!(client.base_url(), "http://localhost:4002");
    }
}
