//! ログインフォーム（login-register-ui-plan.md 3.2）。
//!
//! ```text
//! -------------------------------------------------
//!  Login                          [x close]
//!
//!  Username or Email: [________________]
//!  Password:          [****************]
//!  [v] Remember Me            [ Login ]
//!  [ Lost Password? ]  [ Register Account ]
//! -------------------------------------------------
//! ```

use crate::widgets::{
    centered_panel, form_error, hint_text, small_button, text_field, title_row, BUTTON_NEUTRAL,
    BUTTON_PRIMARY, FORM_PANEL_WIDTH, TEXT_PRIMARY,
};
use auth_client::{AuthClient, AuthError, AuthTask, Session};

/// フォームからホスト（state.rs）へ返す遷移要求。
pub(crate) enum LoginAction {
    None,
    /// ログイン成功。セッションを保持してメニューへ戻る。
    LoggedIn(Box<Session>),
    /// Register Account ボタン。
    GoToRegister,
    /// x ボタン。メニュートップへ戻る。
    CloseToMenu,
}

#[derive(Default)]
pub(crate) struct LoginForm {
    identifier: String,
    password: String,
    remember_me: bool,
    /// フォーム全体のエラー表示（認証失敗・ネットワークエラー）。
    error: Option<String>,
    /// Lost Password? 押下時の未実装案内。
    lost_password_notice: bool,
    /// 実行中の login リクエスト。
    pending: Option<AuthTask<Session>>,
}

impl LoginForm {
    /// 画面に入るたびに呼び、前回の入力・エラー・実行中リクエストを破棄する。
    pub(crate) fn reset(&mut self) {
        *self = Self::default();
    }

    fn poll(&mut self) -> Option<LoginAction> {
        let result = self.pending.as_ref()?.try_take()?;
        self.pending = None;
        match result {
            Ok(session) => {
                // フォームは画面遷移後も SystemUi 内に残るため、平文パスワードを
                // メモリに保持し続けないよう成功時に即座に消去する
                self.password.clear();
                Some(LoginAction::LoggedIn(Box::new(session)))
            }
            Err(AuthError::InvalidCredentials(detail)) => {
                self.error = Some(detail);
                None
            }
            Err(err) => {
                self.error = Some(err.to_string());
                None
            }
        }
    }

    fn submit(&mut self, auth: Option<&AuthClient>) {
        let Some(auth) = auth else {
            self.error = Some("Auth service is not configured.".to_string());
            return;
        };
        self.error = None;
        self.lost_password_notice = false;
        self.pending = Some(auth.login_async(
            self.identifier.trim().to_string(),
            self.password.clone(),
            self.remember_me,
        ));
    }

    fn can_submit(&self) -> bool {
        self.pending.is_none() && !self.identifier.trim().is_empty() && !self.password.is_empty()
    }
}

pub(crate) fn render(
    ctx: &egui::Context,
    form: &mut LoginForm,
    auth: Option<&AuthClient>,
) -> LoginAction {
    if let Some(action) = form.poll() {
        return action;
    }

    let mut action = LoginAction::None;
    let submitting = form.pending.is_some();

    centered_panel(ctx, "system_ui_login", FORM_PANEL_WIDTH, |ui| {
        if title_row(ui, "Login") {
            action = LoginAction::CloseToMenu;
        }
        ui.add_space(12.0);

        let mut submit_requested = false;

        ui.add_enabled_ui(!submitting, |ui| {
            egui::Grid::new("login_fields")
                .num_columns(2)
                .spacing(egui::vec2(10.0, 8.0))
                .show(ui, |ui| {
                    let identifier =
                        text_field(ui, "Username or Email:", &mut form.identifier, false);
                    let password = text_field(ui, "Password:", &mut form.password, true);
                    // Enter キーでも送信できるようにする
                    for response in [identifier, password] {
                        if response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                            submit_requested = true;
                        }
                    }
                });

            ui.add_space(10.0);
            ui.horizontal(|ui| {
                ui.checkbox(
                    &mut form.remember_me,
                    egui::RichText::new("Remember Me").color(TEXT_PRIMARY),
                );
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let login = ui.add_enabled(
                        form.can_submit(),
                        egui::Button::new(
                            egui::RichText::new("Login")
                                .color(egui::Color32::WHITE)
                                .strong(),
                        )
                        .fill(BUTTON_PRIMARY)
                        .min_size(egui::vec2(120.0, 32.0)),
                    );
                    if login.clicked() {
                        submit_requested = true;
                    }
                });
            });
        });

        if submitting {
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.spinner();
                hint_text(ui, "Logging in...");
            });
        }
        if let Some(error) = &form.error {
            ui.add_space(8.0);
            form_error(ui, error);
        }

        ui.add_space(12.0);
        ui.separator();
        ui.add_space(8.0);
        ui.horizontal(|ui| {
            if small_button(ui, "Lost Password?", BUTTON_NEUTRAL) {
                // パスワードリセットは別計画（login-register-ui-plan.md 1.2）
                form.lost_password_notice = true;
            }
            if small_button(ui, "Register Account", BUTTON_NEUTRAL) {
                action = LoginAction::GoToRegister;
            }
        });
        if form.lost_password_notice {
            ui.add_space(6.0);
            hint_text(ui, "Password reset is not available yet.");
        }

        if submit_requested && form.can_submit() {
            form.submit(auth);
        }
    });

    action
}
