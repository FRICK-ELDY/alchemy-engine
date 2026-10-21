//! システムメニューの状態機械とメニュー項目の可視性判定。

use crate::login_form::{LoginAction, LoginForm};
use crate::register_form::{RegisterAction, RegisterForm};
use auth_client::{AuthClient, AuthError, AuthTask, Session, TokenStore};

/// システムメニューの画面遷移。
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Screen {
    /// メニュー非表示（ゲームプレイ中）
    #[default]
    Closed,
    /// メニュートップ（ログイン状態 + Login/Register + Quit）
    Menu,
    /// ログインフォーム
    Login,
    /// アカウント登録フォーム
    Register,
}

/// 認証セッション状態（auth_client のログイン成否を反映する）。
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum SessionState {
    /// 未ログイン
    #[default]
    NotLoggedIn,
    /// ログイン済み（表示用 username を保持）
    LoggedIn { username: String },
}

/// メニュー項目の識別子。可視性判定を一元化するために使う。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MenuItem {
    /// アカウント行（アイコン + ログイン状態表示）と Login/Register / Logout
    Account,
    /// クライアント終了
    Quit,
}

/// メニュー表示条件の判定材料。
///
/// 将来パーソナルエリア概念が実装されたら `in_personal_area` をホストが設定し、
/// ログイン等の機微な操作をパーソナルエリア内に限定できるようにする
/// （login-register-ui-plan.md 1.4 の将来フック）。
#[derive(Clone, Copy, Debug)]
pub struct MenuEnvironment {
    /// サーバ（ルーム）に接続してフレームを受信しているか。
    pub connected: bool,
    /// パーソナルエリア内にいるか。概念が未実装の間は「未接続 = パーソナルエリア相当」
    /// としてホストが `!connected` を渡す。
    pub in_personal_area: bool,
}

impl Default for MenuEnvironment {
    fn default() -> Self {
        Self {
            connected: false,
            in_personal_area: true,
        }
    }
}

/// メニュー項目の可視性を一元判定する。
///
/// 現状は全項目を常時表示とする。パーソナルエリア実装後にここへ条件を足すだけで
/// 全画面の表示制御が変わるよう、判定はこの関数以外に書かないこと。
pub fn item_visible(item: MenuItem, _env: &MenuEnvironment) -> bool {
    match item {
        MenuItem::Account => true,
        MenuItem::Quit => true,
    }
}

/// 利用規約・プライバシーポリシーのリンク先（登録フォームのハイパーリンク）。
///
/// ページ自体の作成はスコープ外のため、既定値は auth 側 config と同じ暫定 URL
/// （login-register-ui-plan.md 3.3）。
#[derive(Clone, Debug)]
pub struct LegalLinks {
    pub tos_url: String,
    pub privacy_policy_url: String,
}

impl Default for LegalLinks {
    fn default() -> Self {
        Self {
            tos_url: "https://alchemy.frick-eldy.com/terms".to_string(),
            privacy_policy_url: "https://alchemy.frick-eldy.com/privacy".to_string(),
        }
    }
}

/// ホスト（イベントループ）が処理すべきイベント。
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SystemUiEvent {
    /// メニューが開いた（ゲーム入力を遮断しカーソルを解放する）
    Opened,
    /// メニューが閉じた（カーソルをサーバ指示の grab 状態へ復帰する）
    Closed,
    /// クライアント終了要求（Quit ボタン）
    QuitRequested,
}

/// システムメニュー本体。
///
/// egui の描画とは独立にテスト可能な純粋状態機械として実装し、
/// 描画は `menu.rs`（Phase 3 以降は `login_form.rs` / `register_form.rs`）が担う。
#[derive(Default)]
pub struct SystemUi {
    screen: Screen,
    session: SessionState,
    env: MenuEnvironment,
    /// auth API クライアント。未設定（URL 不正等）の場合フォームは
    /// "Auth service is not configured." を表示する。
    auth: Option<AuthClient>,
    links: LegalLinks,
    login_form: LoginForm,
    register_form: RegisterForm,
    /// ログイン中のトークン一式。logout / 自動 refresh に使う。
    /// Remember Me OFF ならメモリのみ保持でクライアント終了とともに消える。
    auth_session: Option<Session>,
    /// refresh token の OS 資格情報ストア（Remember Me の永続化先）。
    token_store: Option<TokenStore>,
    /// 起動時自動ログイン（保存済み refresh token による `POST /refresh`）。
    /// 使用中のトークンも保持し、成功時にセッションへ復元する
    /// （refresh 応答には refresh_token が含まれないため）。
    auto_login: Option<(String, AuthTask<Session>)>,
}

impl SystemUi {
    pub fn new() -> Self {
        Self::default()
    }

    /// auth API クライアントを設定する（app 起動時に一度呼ぶ）。
    ///
    /// 資格情報ストアに refresh token が保存されていれば、そのまま
    /// 自動ログイン（`POST /refresh`）をバックグラウンドで開始する
    /// （login-register-ui-plan.md 5.3）。
    pub fn set_auth_client(&mut self, client: AuthClient) {
        self.token_store = TokenStore::for_auth(client.base_url());

        // 同期 load はイベントループ開始前（起動時）の一度だけなので許容する
        if let Some(token) = self.token_store.as_ref().and_then(TokenStore::load) {
            log::info!("stored refresh token found, attempting auto login");
            self.auto_login = Some((token.clone(), client.refresh_async(token)));
        }

        self.auth = Some(client);
    }

    /// 起動時自動ログインが実行中か（メニューの "Signing in..." 表示用）。
    pub fn is_auto_login_pending(&self) -> bool {
        self.auto_login.is_some()
    }

    /// 自動ログインの完了を検出して反映する（毎フレーム呼ばれる）。
    fn poll_auto_login(&mut self) {
        let Some((_, task)) = &self.auto_login else {
            return;
        };
        let Some(result) = task.try_take() else {
            return;
        };
        let Some((used_token, _)) = self.auto_login.take() else {
            return;
        };

        match result {
            Ok(mut session) => {
                log::info!("auto login succeeded as {}", session.user.username);
                // refresh 応答に refresh_token は含まれない（トークン自体は
                // 継続使用でサーバ側の last_used_at がスライドする）ため、
                // ログアウト時の revoke 用に使用したトークンをセッションへ復元する。
                // ストアの保存内容もそのまま維持する
                session.refresh_token = Some(used_token);
                self.apply_session_state(session);
            }
            Err(AuthError::InvalidCredentials(_)) => {
                // 7 日超過・revoke 済み等。無効なトークンは破棄する
                log::info!("stored refresh token is no longer valid, discarding");
                if let Some(store) = &self.token_store {
                    store.clear_in_background();
                }
            }
            Err(e) => {
                // ネットワークエラー等はトークンを保持したまま未ログインで続行
                // （次回起動時に再試行される）
                log::warn!("auto login failed: {e}");
            }
        }
    }

    /// 利用規約・プライバシーポリシーのリンク先を設定する。
    pub fn set_legal_links(&mut self, links: LegalLinks) {
        self.links = links;
    }

    /// メニュー（いずれかの画面）が開いているか。
    /// 真の間、ホストはゲーム入力（movement/キー）を遮断する。
    pub fn is_open(&self) -> bool {
        self.screen != Screen::Closed
    }

    pub fn screen(&self) -> Screen {
        self.screen
    }

    pub fn session(&self) -> &SessionState {
        &self.session
    }

    /// ホストが毎フレーム接続状態を伝える。
    /// パーソナルエリア概念が未実装の間は「未接続 = パーソナルエリア相当」とする。
    pub fn set_connected(&mut self, connected: bool) {
        self.env.connected = connected;
        self.env.in_personal_area = !connected;
    }

    pub fn environment(&self) -> &MenuEnvironment {
        &self.env
    }

    /// セッション表示状態を直接設定する（テスト・Phase 4 の自動ログイン用）。
    pub fn set_session(&mut self, session: SessionState) {
        self.session = session;
    }

    /// ログイン中のトークン一式（Phase 4 の logout / refresh 用）。
    pub fn auth_session(&self) -> Option<&Session> {
        self.auth_session.as_ref()
    }

    /// ログアウト等でセッションを破棄し未ログイン表示へ戻す（ローカルのみ）。
    pub fn clear_session(&mut self) {
        self.auth_session = None;
        self.session = SessionState::NotLoggedIn;
    }

    /// ログアウトする。auth の `POST /logout`（access token 失効 +
    /// refresh token revoke）をバックグラウンドで投げ、ローカルの
    /// トークンと資格情報ストアの保存分を破棄する。
    pub fn logout(&mut self) {
        if let (Some(auth), Some(session)) = (&self.auth, &self.auth_session) {
            // refresh token はメモリ上のセッションが常に持っている
            // （手動ログイン時はレスポンス由来、自動ログイン時は復元済み）ため、
            // GUI スレッドをブロックするストアの再読込は行わない
            auth.logout_in_background(session.access_token.clone(), session.refresh_token.clone());
        }
        if let Some(store) = &self.token_store {
            store.clear_in_background();
        }
        self.clear_session();
    }

    /// ログイン/登録成功時にトークンを保持し、Remember Me を永続化する。
    fn adopt_session(&mut self, session: Session) {
        // 自動ログインが進行中でも手動ログインの結果を優先する
        self.auto_login = None;
        if let Some(store) = &self.token_store {
            match &session.refresh_token {
                // Remember Me ON: 次回起動の自動ログイン用に保存
                Some(token) => store.save_in_background(token.clone()),
                // Remember Me OFF: 以前のトークンが残っていると別条件で
                // 自動ログインしてしまうため消す
                None => store.clear_in_background(),
            }
        }
        self.apply_session_state(session);
    }

    /// セッションをメモリに反映する（ストアには触れない）。
    fn apply_session_state(&mut self, session: Session) {
        self.session = SessionState::LoggedIn {
            username: session.user.username.clone(),
        };
        self.auth_session = Some(session);
    }

    /// ESC 押下。開いていなければメニューを開き、
    /// フォーム表示中はメニュートップへ戻り、メニュートップなら閉じる。
    pub fn handle_escape(&mut self) -> Option<SystemUiEvent> {
        match self.screen {
            Screen::Closed => {
                self.screen = Screen::Menu;
                Some(SystemUiEvent::Opened)
            }
            Screen::Login | Screen::Register => {
                self.screen = Screen::Menu;
                None
            }
            Screen::Menu => {
                self.screen = Screen::Closed;
                Some(SystemUiEvent::Closed)
            }
        }
    }

    /// メニューを閉じる（xボタン等）。
    pub fn close(&mut self) -> Option<SystemUiEvent> {
        if self.screen == Screen::Closed {
            return None;
        }
        self.screen = Screen::Closed;
        Some(SystemUiEvent::Closed)
    }

    pub(crate) fn go_to(&mut self, screen: Screen) {
        // フォーム画面に入るたびに前回の入力（パスワード含む）・エラー・
        // 実行中リクエストを破棄する
        match screen {
            Screen::Login => self.login_form.reset(),
            Screen::Register => self.register_form.reset(),
            _ => {}
        }
        self.screen = screen;
    }

    /// システムメニューを egui overlay として描画する。
    /// Canvas UI（ゲーム内 UI）の後に呼ぶことで最前面に表示される。
    pub fn render(&mut self, ctx: &egui::Context) -> Option<SystemUiEvent> {
        // 自動ログインはメニューの開閉に関係なく進行させる（毎フレーム呼ばれる）
        self.poll_auto_login();

        match self.screen {
            Screen::Closed => None,
            Screen::Menu => crate::menu::render_menu(ctx, self),
            Screen::Login => {
                let action =
                    crate::login_form::render(ctx, &mut self.login_form, self.auth.as_ref());
                match action {
                    LoginAction::None => {}
                    LoginAction::LoggedIn(session) => {
                        self.adopt_session(*session);
                        self.go_to(Screen::Menu);
                    }
                    LoginAction::GoToRegister => self.go_to(Screen::Register),
                    LoginAction::CloseToMenu => self.go_to(Screen::Menu),
                }
                None
            }
            Screen::Register => {
                let action = crate::register_form::render(
                    ctx,
                    &mut self.register_form,
                    self.auth.as_ref(),
                    &self.links,
                );
                match action {
                    RegisterAction::None => {}
                    RegisterAction::Registered(session) => {
                        self.adopt_session(*session);
                        self.go_to(Screen::Menu);
                    }
                    RegisterAction::CloseToMenu => self.go_to(Screen::Menu),
                }
                None
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_toggles_menu() {
        let mut sys = SystemUi::new();
        assert!(!sys.is_open());

        assert_eq!(sys.handle_escape(), Some(SystemUiEvent::Opened));
        assert!(sys.is_open());
        assert_eq!(sys.screen(), Screen::Menu);

        assert_eq!(sys.handle_escape(), Some(SystemUiEvent::Closed));
        assert!(!sys.is_open());
    }

    #[test]
    fn escape_from_form_returns_to_menu_without_closing() {
        let mut sys = SystemUi::new();
        sys.handle_escape();
        sys.go_to(Screen::Login);

        // フォーム → メニュートップ（Closed イベントは出ない）
        assert_eq!(sys.handle_escape(), None);
        assert_eq!(sys.screen(), Screen::Menu);
        assert!(sys.is_open());

        sys.go_to(Screen::Register);
        assert_eq!(sys.handle_escape(), None);
        assert_eq!(sys.screen(), Screen::Menu);
    }

    #[test]
    fn close_emits_event_only_when_open() {
        let mut sys = SystemUi::new();
        assert_eq!(sys.close(), None);

        sys.handle_escape();
        assert_eq!(sys.close(), Some(SystemUiEvent::Closed));
        assert!(!sys.is_open());
    }

    #[test]
    fn connected_state_drives_personal_area_placeholder() {
        let mut sys = SystemUi::new();
        // 未接続 = パーソナルエリア相当
        assert!(sys.environment().in_personal_area);

        sys.set_connected(true);
        assert!(sys.environment().connected);
        assert!(!sys.environment().in_personal_area);

        sys.set_connected(false);
        assert!(sys.environment().in_personal_area);
    }

    #[test]
    fn all_items_visible_by_default() {
        let env = MenuEnvironment::default();
        assert!(item_visible(MenuItem::Account, &env));
        assert!(item_visible(MenuItem::Quit, &env));
    }

    #[test]
    fn auto_login_is_not_pending_without_auth_client() {
        let sys = SystemUi::new();
        assert!(!sys.is_auto_login_pending());
    }

    #[test]
    fn logout_without_auth_client_still_clears_session() {
        let mut sys = SystemUi::new();
        sys.set_session(SessionState::LoggedIn {
            username: "alice".to_string(),
        });

        sys.logout();
        assert_eq!(*sys.session(), SessionState::NotLoggedIn);
        assert!(sys.auth_session().is_none());
    }

    #[test]
    fn clear_session_returns_to_not_logged_in() {
        let mut sys = SystemUi::new();
        sys.set_session(SessionState::LoggedIn {
            username: "alice".to_string(),
        });

        sys.clear_session();
        assert_eq!(*sys.session(), SessionState::NotLoggedIn);
        assert!(sys.auth_session().is_none());
    }

    #[test]
    fn session_state_updates() {
        let mut sys = SystemUi::new();
        assert_eq!(*sys.session(), SessionState::NotLoggedIn);

        sys.set_session(SessionState::LoggedIn {
            username: "alice".to_string(),
        });
        assert_eq!(
            *sys.session(),
            SessionState::LoggedIn {
                username: "alice".to_string()
            }
        );
    }
}
