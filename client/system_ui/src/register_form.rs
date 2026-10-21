//! アカウント登録フォーム（login-register-ui-plan.md 3.3）。
//!
//! ```text
//! -------------------------------------------------
//!  Register Account               [x close]
//!
//!  Username:        [________________]
//!  Email:           [________________]
//!  Repeat Email:    [________________]
//!  Password:        [****************]
//!    (at least 8 characters, 1 digit, 1 lowercase, 1 uppercase)
//!  Repeat Password: [****************]
//!  [v] Remember Me (logs out after 7 days of inactivity)
//!  Birth Day:  [month v] [day v] [year v]
//!  Promo Code: [________________]   (optional)
//!  [v] I agree to the [Terms of Service] and [Privacy Policy]
//!  [ Register Account ]
//! -------------------------------------------------
//! ```
//!
//! Register ボタンはクライアント側バリデーションが全て通るまで disabled。
//! `repeat_email` / `repeat_password` は API に送らない（クライアント検証のみ）。

use crate::state::LegalLinks;
use crate::validation::{
    days_in_month, today_utc, validate_birthday, validate_email, validate_password,
    validate_username, PASSWORD_HINT,
};
use crate::widgets::{
    centered_panel, field_error_row, form_error, hint_text, text_field, title_row, BUTTON_PRIMARY,
    FORM_PANEL_WIDTH, TEXT_MUTED, TEXT_PRIMARY,
};
use auth_client::{AuthClient, AuthError, AuthTask, FieldErrors, RegisterRequest, Session};

/// フォームからホスト（state.rs）へ返す遷移要求。
pub(crate) enum RegisterAction {
    None,
    /// 登録成功（auth は login と同形式のトークンを返す）。そのままログイン済みにする。
    Registered(Box<Session>),
    /// x ボタン。メニュートップへ戻る。
    CloseToMenu,
}

#[derive(Default)]
pub(crate) struct RegisterForm {
    username: String,
    email: String,
    repeat_email: String,
    password: String,
    repeat_password: String,
    remember_me: bool,
    birth_month: Option<u32>,
    birth_day: Option<u32>,
    birth_year: Option<i32>,
    promo_code: String,
    tos_agreed: bool,
    /// 422 レスポンスのフィールド別サーバエラー。
    server_errors: FieldErrors,
    /// フォーム全体のエラー（ネットワークエラー等）。
    error: Option<String>,
    /// 実行中の register リクエスト。
    pending: Option<AuthTask<Session>>,
}

impl RegisterForm {
    /// 画面に入るたびに呼び、前回の入力・エラー・実行中リクエストを破棄する。
    pub(crate) fn reset(&mut self) {
        *self = Self::default();
    }

    fn poll(&mut self) -> Option<RegisterAction> {
        let result = self.pending.as_ref()?.try_take()?;
        self.pending = None;
        match result {
            Ok(session) => {
                // フォームは画面遷移後も SystemUi 内に残るため、平文パスワードを
                // メモリに保持し続けないよう成功時に即座に消去する
                self.password.clear();
                self.repeat_password.clear();
                Some(RegisterAction::Registered(Box::new(session)))
            }
            Err(AuthError::Validation { detail, fields }) => {
                self.server_errors = fields;
                self.error = if self.server_errors.is_empty() {
                    Some(detail)
                } else {
                    None
                };
                None
            }
            Err(err) => {
                self.error = Some(err.to_string());
                None
            }
        }
    }

    /// クライアント側バリデーション（3.4）。フィールド名 → エラーメッセージ。
    ///
    /// 入力途中のフィールドを赤くしないよう、表示側は「入力済みのフィールドのみ」
    /// エラーを出す。送信可否は全フィールドで判定する。
    fn client_error(&self, field: &str) -> Option<&'static str> {
        match field {
            "username" => validate_username(&self.username).err(),
            "email" => validate_email(&self.email).err(),
            "repeat_email" => (self.repeat_email != self.email).then_some("emails do not match"),
            "password" => validate_password(&self.password).err(),
            "repeat_password" => {
                (self.repeat_password != self.password).then_some("passwords do not match")
            }
            "birthday" => match (self.birth_year, self.birth_month, self.birth_day) {
                (Some(y), Some(m), Some(d)) => validate_birthday(y, m, d).err(),
                _ => Some("select your birth date"),
            },
            _ => None,
        }
    }

    fn all_valid(&self) -> bool {
        const FIELDS: [&str; 6] = [
            "username",
            "email",
            "repeat_email",
            "password",
            "repeat_password",
            "birthday",
        ];
        FIELDS.iter().all(|f| self.client_error(f).is_none()) && self.tos_agreed
    }

    fn can_submit(&self) -> bool {
        self.pending.is_none() && self.all_valid()
    }

    fn submit(&mut self, auth: Option<&AuthClient>) {
        let Some(auth) = auth else {
            self.error = Some("Auth service is not configured.".to_string());
            return;
        };
        let (Some(year), Some(month), Some(day)) =
            (self.birth_year, self.birth_month, self.birth_day)
        else {
            return;
        };
        self.error = None;
        self.server_errors.clear();

        let promo_code = self.promo_code.trim();
        let request = RegisterRequest {
            username: self.username.trim().to_string(),
            email: self.email.trim().to_string(),
            password: self.password.clone(),
            birthday: format!("{year:04}-{month:02}-{day:02}"),
            promo_code: (!promo_code.is_empty()).then(|| promo_code.to_string()),
            tos_agreed: self.tos_agreed,
            remember_me: self.remember_me,
        };
        self.pending = Some(auth.register_async(request));
    }
}

pub(crate) fn render(
    ctx: &egui::Context,
    form: &mut RegisterForm,
    auth: Option<&AuthClient>,
    links: &LegalLinks,
) -> RegisterAction {
    if let Some(action) = form.poll() {
        return action;
    }

    let mut action = RegisterAction::None;
    let submitting = form.pending.is_some();

    centered_panel(ctx, "system_ui_register", FORM_PANEL_WIDTH, |ui| {
        if title_row(ui, "Register Account") {
            action = RegisterAction::CloseToMenu;
        }
        ui.add_space(12.0);

        ui.add_enabled_ui(!submitting, |ui| {
            render_fields(ui, form);
            ui.add_space(10.0);
            render_remember_me(ui, form);
            ui.add_space(6.0);
            render_birthday(ui, form);
            ui.add_space(6.0);
            render_promo_code(ui, form);
            ui.add_space(10.0);
            render_tos(ui, form, links);
            ui.add_space(12.0);

            let register = ui.add_enabled(
                form.can_submit(),
                egui::Button::new(
                    egui::RichText::new("Register Account")
                        .color(egui::Color32::WHITE)
                        .strong(),
                )
                .fill(BUTTON_PRIMARY)
                .min_size(egui::vec2(FORM_PANEL_WIDTH, 36.0)),
            );
            if register.clicked() {
                form.submit(auth);
            }
        });

        if submitting {
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.spinner();
                hint_text(ui, "Creating account...");
            });
        }
        if let Some(error) = &form.error {
            ui.add_space(8.0);
            form_error(ui, error);
        }
    });

    action
}

/// テキスト入力フィールド群。入力済みのフィールドにだけクライアントエラーを表示し、
/// サーバエラー（422）は常に表示する。
fn render_fields(ui: &mut egui::Ui, form: &mut RegisterForm) {
    egui::Grid::new("register_fields")
        .num_columns(2)
        .spacing(egui::vec2(10.0, 6.0))
        .show(ui, |ui| {
            text_field(ui, "Username:", &mut form.username, false);
            show_errors(ui, form, "username", !form.username.is_empty());

            text_field(ui, "Email:", &mut form.email, false);
            show_errors(ui, form, "email", !form.email.is_empty());

            text_field(ui, "Repeat Email:", &mut form.repeat_email, false);
            show_errors(ui, form, "repeat_email", !form.repeat_email.is_empty());

            text_field(ui, "Password:", &mut form.password, true);
            // パスワード要件は常時ヒント表示（スペック 3.3）
            ui.label("");
            ui.label(
                egui::RichText::new(format!("({PASSWORD_HINT})"))
                    .color(TEXT_MUTED)
                    .size(12.0),
            );
            ui.end_row();
            show_errors(ui, form, "password", !form.password.is_empty());

            text_field(ui, "Repeat Password:", &mut form.repeat_password, true);
            show_errors(
                ui,
                form,
                "repeat_password",
                !form.repeat_password.is_empty(),
            );
        });
}

/// フィールドの直下にクライアント/サーバエラーを表示する（Grid の行として）。
fn show_errors(ui: &mut egui::Ui, form: &RegisterForm, field: &str, touched: bool) {
    if touched {
        if let Some(message) = form.client_error(field) {
            field_error_row(ui, message);
            return; // クライアントエラーが出ている間はサーバエラーは冗長なので省く
        }
    }
    if let Some(messages) = form.server_errors.get(field) {
        for message in messages {
            field_error_row(ui, message);
        }
    }
}

fn render_remember_me(ui: &mut egui::Ui, form: &mut RegisterForm) {
    ui.checkbox(
        &mut form.remember_me,
        egui::RichText::new("Remember Me (logs out after 7 days of inactivity)")
            .color(TEXT_PRIMARY),
    );
}

fn render_birthday(ui: &mut egui::Ui, form: &mut RegisterForm) {
    ui.horizontal(|ui| {
        ui.label(egui::RichText::new("Birth Day:").color(TEXT_PRIMARY));

        egui::ComboBox::from_id_salt("birth_month")
            .width(80.0)
            .selected_text(
                form.birth_month
                    .map_or_else(|| "month".to_string(), |m| format!("{m:02}")),
            )
            .show_ui(ui, |ui| {
                for month in 1..=12u32 {
                    ui.selectable_value(&mut form.birth_month, Some(month), format!("{month:02}"));
                }
            });

        let max_day = days_in_month(
            form.birth_year.unwrap_or(2000),
            form.birth_month.unwrap_or(1),
        );
        egui::ComboBox::from_id_salt("birth_day")
            .width(70.0)
            .selected_text(
                form.birth_day
                    .map_or_else(|| "day".to_string(), |d| format!("{d:02}")),
            )
            .show_ui(ui, |ui| {
                for day in 1..=max_day {
                    ui.selectable_value(&mut form.birth_day, Some(day), format!("{day:02}"));
                }
            });

        let current_year = today_utc().0;
        egui::ComboBox::from_id_salt("birth_year")
            .width(80.0)
            .selected_text(
                form.birth_year
                    .map_or_else(|| "year".to_string(), |y| y.to_string()),
            )
            .show_ui(ui, |ui| {
                for year in ((current_year - 119)..=current_year).rev() {
                    ui.selectable_value(&mut form.birth_year, Some(year), year.to_string());
                }
            });
    });

    // 月・年の変更で日が範囲外になったら詰める（例: 03-31 → 02 に変更）
    if let (Some(day), Some(month)) = (form.birth_day, form.birth_month) {
        let max_day = days_in_month(form.birth_year.unwrap_or(2000), month);
        if day > max_day {
            form.birth_day = Some(max_day);
        }
    }

    let touched =
        form.birth_year.is_some() && form.birth_month.is_some() && form.birth_day.is_some();
    if touched {
        if let Some(message) = form.client_error("birthday") {
            form_error(ui, message);
        }
    }
    if let Some(messages) = form.server_errors.get("birthday") {
        for message in messages {
            form_error(ui, message);
        }
    }
}

fn render_promo_code(ui: &mut egui::Ui, form: &mut RegisterForm) {
    ui.horizontal(|ui| {
        ui.label(egui::RichText::new("Promo Code:").color(TEXT_PRIMARY));
        ui.add(egui::TextEdit::singleline(&mut form.promo_code).desired_width(160.0));
        hint_text(ui, "(optional)");
    });
}

fn render_tos(ui: &mut egui::Ui, form: &mut RegisterForm, links: &LegalLinks) {
    ui.horizontal_wrapped(|ui| {
        ui.checkbox(&mut form.tos_agreed, "");
        ui.label(egui::RichText::new("I agree to the").color(TEXT_PRIMARY));
        ui.hyperlink_to("Terms of Service", &links.tos_url);
        ui.label(egui::RichText::new("and").color(TEXT_PRIMARY));
        ui.hyperlink_to("Privacy Policy", &links.privacy_policy_url);
    });
    if let Some(messages) = form.server_errors.get("tos_agreed") {
        for message in messages {
            form_error(ui, message);
        }
    }
}
