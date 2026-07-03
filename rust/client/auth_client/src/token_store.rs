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
//!
//! # スレッドとブロッキング
//!
//! ストアへのアクセスは OS API / DBus 呼び出しを伴い GUI スレッドを
//! ブロックし得るため、フレーム処理中の書き込み・削除は
//! [`TokenStore::save_in_background`] / [`TokenStore::clear_in_background`] を使う。
//! 同期版はイベントループ開始前（起動時の [`TokenStore::load`]）とテスト用。

use keyring::Entry;

/// 資格情報ストアのサービス名（Credential Manager 等での表示名）。
const SERVICE: &str = "VRAlchemy";

/// refresh token の保管先。
///
/// アカウント名を auth のベース URL で分けるので、開発（localhost）と本番の
/// トークンが衝突しない。`Clone` は同じ保管先を指す（バックグラウンド操作用）。
#[derive(Clone)]
pub struct TokenStore {
    account: String,
}

impl TokenStore {
    /// 指定した auth ベース URL 用のストアを開く。
    ///
    /// ストアが利用できない環境（対応ストアの無いプラットフォーム等）では
    /// `None` を返し、呼び出し側は「保存なし」として動作を続ける。
    pub fn for_auth(base_url: &str) -> Option<Self> {
        let account = format!("refresh_token:{base_url}");
        // Entry 生成はストアに触れない軽量な操作だが、パラメータ不正や
        // ストア未対応をここで一度だけ検出しておく
        match Entry::new(SERVICE, &account) {
            Ok(_) => Some(Self { account }),
            Err(e) => {
                log::warn!("credential store unavailable, remember me disabled: {e}");
                None
            }
        }
    }

    fn entry(&self) -> Result<Entry, keyring::Error> {
        Entry::new(SERVICE, &self.account)
    }

    /// refresh token を保存する（既存があれば上書き）。GUI スレッドからは
    /// [`TokenStore::save_in_background`] を使うこと。
    pub fn save(&self, token: &str) {
        if let Err(e) = self.entry().and_then(|entry| entry.set_password(token)) {
            log::warn!("failed to save refresh token to credential store: {e}");
        }
    }

    /// refresh token をバックグラウンドスレッドで保存する（GUI スレッド用）。
    pub fn save_in_background(&self, token: String) {
        let store = self.clone();
        std::thread::spawn(move || store.save(&token));
    }

    /// 保存済みの refresh token を読む。未保存なら `None`。
    ///
    /// 同期呼び出しのため、イベントループ開始前（起動時）にのみ使うこと。
    pub fn load(&self) -> Option<String> {
        match self.entry().and_then(|entry| entry.get_password()) {
            Ok(token) => Some(token),
            Err(keyring::Error::NoEntry) => None,
            Err(e) => {
                log::warn!("failed to read refresh token from credential store: {e}");
                None
            }
        }
    }

    /// 保存済みの refresh token を削除する（未保存なら何もしない）。
    /// GUI スレッドからは [`TokenStore::clear_in_background`] を使うこと。
    pub fn clear(&self) {
        match self.entry().and_then(|entry| entry.delete_credential()) {
            Ok(()) | Err(keyring::Error::NoEntry) => {}
            Err(e) => log::warn!("failed to delete refresh token from credential store: {e}"),
        }
    }

    /// 保存済みの refresh token をバックグラウンドスレッドで削除する（GUI スレッド用）。
    pub fn clear_in_background(&self) {
        let store = self.clone();
        std::thread::spawn(move || store.clear());
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
