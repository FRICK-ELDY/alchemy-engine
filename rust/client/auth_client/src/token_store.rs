//! refresh token の OS 資格情報ストア保管（login-register-ui-plan.md 4.3）。
//!
//! Remember Me ON のときだけ refresh token を保存し、次回起動時の自動ログイン
//! （`POST /refresh`）に使う。保存先は OS ネイティブのストア:
//!
//! - Windows: Credential Manager
//! - macOS: Keychain
//! - Linux: Secret Service（Gnome Keyring / KWallet）
//!
//! access token は保存しない（メモリのみ）。Remember Me OFF なら何も保存しない。

use keyring::Entry;

/// 資格情報ストアのサービス名（Credential Manager 等での表示名）。
const SERVICE: &str = "VRAlchemy";

/// refresh token の保管先。
///
/// アカウント名を auth のベース URL で分けるので、開発（localhost）と本番の
/// トークンが衝突しない。
pub struct TokenStore {
    entry: Entry,
}

impl TokenStore {
    /// 指定した auth ベース URL 用のストアを開く。
    ///
    /// ストアが利用できない環境（対応ストアの無いプラットフォーム等）では
    /// `None` を返し、呼び出し側は「保存なし」として動作を続ける。
    pub fn for_auth(base_url: &str) -> Option<Self> {
        match Entry::new(SERVICE, &format!("refresh_token:{base_url}")) {
            Ok(entry) => Some(Self { entry }),
            Err(e) => {
                log::warn!("credential store unavailable, remember me disabled: {e}");
                None
            }
        }
    }

    /// refresh token を保存する（既存があれば上書き）。
    pub fn save(&self, token: &str) {
        if let Err(e) = self.entry.set_password(token) {
            log::warn!("failed to save refresh token to credential store: {e}");
        }
    }

    /// 保存済みの refresh token を読む。未保存なら `None`。
    pub fn load(&self) -> Option<String> {
        match self.entry.get_password() {
            Ok(token) => Some(token),
            Err(keyring::Error::NoEntry) => None,
            Err(e) => {
                log::warn!("failed to read refresh token from credential store: {e}");
                None
            }
        }
    }

    /// 保存済みの refresh token を削除する（未保存なら何もしない）。
    pub fn clear(&self) {
        match self.entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => {}
            Err(e) => log::warn!("failed to delete refresh token from credential store: {e}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 実際の OS 資格情報ストアに書き込むため、手動実行専用:
    /// `cargo test -p auth_client -- --ignored token_store`
    #[test]
    #[ignore = "writes to the real OS credential store"]
    fn save_load_clear_roundtrip() {
        let store = TokenStore::for_auth("http://localhost:9999/test-only").expect("store");
        store.clear();
        assert_eq!(store.load(), None);

        store.save("token-abc");
        assert_eq!(store.load(), Some("token-abc".to_string()));

        store.save("token-def");
        assert_eq!(store.load(), Some("token-def".to_string()));

        store.clear();
        assert_eq!(store.load(), None);
    }
}
