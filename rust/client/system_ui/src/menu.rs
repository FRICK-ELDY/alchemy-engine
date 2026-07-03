//! ESC メニュートップの描画。
//!
//! ```text
//! -------------------------------------
//!  [icon]  Not logged in user          <- ログイン済みなら username
//!  [ Login/Register ]                  <- ログイン済みなら [ Logout ]
//! -------------------------------------
//!  [ Quit ]
//! -------------------------------------
//! ```

use crate::state::{item_visible, MenuItem, Screen, SessionState, SystemUi, SystemUiEvent};
use crate::widgets::{
    centered_panel, menu_button, BUTTON_DANGER, BUTTON_NEUTRAL, BUTTON_PRIMARY, MENU_PANEL_WIDTH,
    TEXT_MUTED, TEXT_PRIMARY,
};

/// メニュートップを描画する。
pub(crate) fn render_menu(ctx: &egui::Context, sys: &mut SystemUi) -> Option<SystemUiEvent> {
    let mut event: Option<SystemUiEvent> = None;
    let env = *sys.environment();
    let session = sys.session().clone();

    centered_panel(ctx, "system_ui_menu", MENU_PANEL_WIDTH, |ui| {
        ui.vertical_centered_justified(|ui| {
            ui.label(
                egui::RichText::new("Menu")
                    .color(TEXT_PRIMARY)
                    .size(22.0)
                    .strong(),
            );
            ui.add_space(12.0);

            if item_visible(MenuItem::Account, &env) {
                render_account_section(ui, sys, &session);
                ui.add_space(8.0);
                ui.separator();
                ui.add_space(8.0);
            }

            if item_visible(MenuItem::Quit, &env) && menu_button(ui, "Quit", BUTTON_DANGER) {
                event = Some(SystemUiEvent::QuitRequested);
            }
        });
    });

    event
}

/// アカウント行（icon + 状態表示）と Login/Register / Logout ボタン。
fn render_account_section(ui: &mut egui::Ui, sys: &mut SystemUi, session: &SessionState) {
    ui.horizontal(|ui| {
        render_account_icon(ui, session);
        ui.add_space(8.0);
        match session {
            SessionState::NotLoggedIn if sys.is_auto_login_pending() => {
                // 起動時自動ログイン（保存済み refresh token の検証）中
                ui.spinner();
                ui.label(
                    egui::RichText::new("Signing in...")
                        .color(TEXT_MUTED)
                        .size(16.0),
                );
            }
            SessionState::NotLoggedIn => {
                ui.label(
                    egui::RichText::new("Not logged in user")
                        .color(TEXT_MUTED)
                        .size(16.0),
                );
            }
            SessionState::LoggedIn { username } => {
                ui.label(
                    egui::RichText::new(username)
                        .color(TEXT_PRIMARY)
                        .size(16.0)
                        .strong(),
                );
            }
        }
    });
    ui.add_space(8.0);

    match session {
        SessionState::NotLoggedIn => {
            if menu_button(ui, "Login/Register", BUTTON_PRIMARY) {
                sys.go_to(Screen::Login);
            }
        }
        SessionState::LoggedIn { .. } => {
            // POST /logout（access token 失効 + refresh token revoke）+ ローカル破棄
            if menu_button(ui, "Logout", BUTTON_NEUTRAL) {
                sys.logout();
            }
        }
    }
}

/// アカウントアイコン。未ログインはグレーの人型シルエット、ログイン済みは青系。
fn render_account_icon(ui: &mut egui::Ui, session: &SessionState) {
    let size = 32.0;
    let (rect, _) = ui.allocate_exact_size(egui::vec2(size, size), egui::Sense::hover());
    let painter = ui.painter();
    let (bg, fg) = match session {
        SessionState::NotLoggedIn => (
            egui::Color32::from_rgb(60, 62, 70),
            egui::Color32::from_rgb(130, 133, 145),
        ),
        SessionState::LoggedIn { .. } => (
            egui::Color32::from_rgb(45, 80, 130),
            egui::Color32::from_rgb(180, 210, 250),
        ),
    };
    painter.circle_filled(rect.center(), size / 2.0, bg);
    // 頭
    painter.circle_filled(
        rect.center() - egui::vec2(0.0, size * 0.14),
        size * 0.16,
        fg,
    );
    // 肩（下半分の弧の代わりに塗り潰し半円っぽい矩形+円で簡易表現）
    painter.circle_filled(
        rect.center() + egui::vec2(0.0, size * 0.26),
        size * 0.24,
        fg,
    );
}
