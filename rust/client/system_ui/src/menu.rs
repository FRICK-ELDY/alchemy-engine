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

const PANEL_FILL: egui::Color32 = egui::Color32::from_rgba_premultiplied(12, 14, 20, 235);
const PANEL_STROKE: egui::Color32 = egui::Color32::from_rgb(90, 110, 150);
const TEXT_PRIMARY: egui::Color32 = egui::Color32::from_rgb(230, 232, 240);
const TEXT_MUTED: egui::Color32 = egui::Color32::from_rgb(150, 155, 170);
const BUTTON_PRIMARY: egui::Color32 = egui::Color32::from_rgb(60, 120, 200);
const BUTTON_NEUTRAL: egui::Color32 = egui::Color32::from_rgb(70, 72, 82);
const BUTTON_DANGER: egui::Color32 = egui::Color32::from_rgb(140, 55, 55);

const PANEL_WIDTH: f32 = 320.0;
const BUTTON_SIZE: egui::Vec2 = egui::vec2(280.0, 40.0);

/// 画面全体を薄暗くするオーバーレイ。メニューがゲーム画面より前面であることを示す。
///
/// ゲーム内 Canvas UI（ダイアログ含む）は `Order::Foreground` を使うため、
/// バックドロップは `Foreground`、メニュー本体は一段上の `Tooltip` に置く。
/// 同一 Order だとバックドロップをクリックした際にレイヤーが最前面へ
/// 並べ替えられ、メニューのボタンが押せなくなるため Order を分離する。
fn render_backdrop(ctx: &egui::Context) {
    egui::Area::new(egui::Id::new("system_ui_backdrop"))
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .interactable(true)
        .show(ctx, |ui| {
            let screen = ui.ctx().screen_rect();
            // クリック・ドラッグがゲーム側 UI に抜けないよう全面で入力を受ける
            // （egui 0.31 に Sense::all() は無いため click_and_drag が最大）
            ui.allocate_rect(screen, egui::Sense::click_and_drag());
            ui.painter().rect_filled(
                screen,
                0.0,
                egui::Color32::from_rgba_premultiplied(0, 0, 0, 120),
            );
        });
}

fn panel_frame() -> egui::Frame {
    egui::Frame::new()
        .fill(PANEL_FILL)
        .inner_margin(egui::Margin::symmetric(20, 18))
        .corner_radius(10.0)
        .stroke(egui::Stroke::new(1.5, PANEL_STROKE))
}

fn menu_button(ui: &mut egui::Ui, label: &str, fill: egui::Color32) -> bool {
    ui.add(
        egui::Button::new(
            egui::RichText::new(label)
                .color(egui::Color32::WHITE)
                .strong(),
        )
        .fill(fill)
        .min_size(BUTTON_SIZE),
    )
    .clicked()
}

/// メニュートップを描画する。
pub(crate) fn render_menu(ctx: &egui::Context, sys: &mut SystemUi) -> Option<SystemUiEvent> {
    render_backdrop(ctx);

    let mut event: Option<SystemUiEvent> = None;
    let env = *sys.environment();
    let session = sys.session().clone();

    egui::Area::new(egui::Id::new("system_ui_menu"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Tooltip)
        .show(ctx, |ui| {
            panel_frame().show(ui, |ui| {
                ui.set_width(PANEL_WIDTH);
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

                    if item_visible(MenuItem::Quit, &env) && menu_button(ui, "Quit", BUTTON_DANGER)
                    {
                        event = Some(SystemUiEvent::QuitRequested);
                    }
                });
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
            // Phase 4 でログアウト処理（auth /logout + トークン破棄）を接続する
            if menu_button(ui, "Logout", BUTTON_NEUTRAL) {
                sys.set_session(SessionState::NotLoggedIn);
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

/// Phase 3 のフォーム実装までのプレースホルダ画面。
pub(crate) fn render_form_placeholder(
    ctx: &egui::Context,
    sys: &mut SystemUi,
) -> Option<SystemUiEvent> {
    render_backdrop(ctx);

    let title = match sys.screen() {
        Screen::Login => "Login",
        Screen::Register => "Register Account",
        _ => "",
    };

    egui::Area::new(egui::Id::new("system_ui_form_placeholder"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Tooltip)
        .show(ctx, |ui| {
            panel_frame().show(ui, |ui| {
                ui.set_width(PANEL_WIDTH);
                ui.horizontal(|ui| {
                    ui.label(
                        egui::RichText::new(title)
                            .color(TEXT_PRIMARY)
                            .size(20.0)
                            .strong(),
                    );
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui
                            .add(
                                egui::Button::new(egui::RichText::new("x").strong())
                                    .fill(BUTTON_NEUTRAL),
                            )
                            .clicked()
                        {
                            sys.go_to(Screen::Menu);
                        }
                    });
                });
                ui.add_space(16.0);
                ui.label(
                    egui::RichText::new("Coming soon (Phase 3).")
                        .color(TEXT_MUTED)
                        .size(14.0),
                );
                ui.add_space(8.0);
                if ui
                    .add(
                        egui::Button::new(egui::RichText::new("Back").color(egui::Color32::WHITE))
                            .fill(BUTTON_NEUTRAL)
                            .min_size(egui::vec2(120.0, 32.0)),
                    )
                    .clicked()
                {
                    sys.go_to(Screen::Menu);
                }
            });
        });

    None
}
