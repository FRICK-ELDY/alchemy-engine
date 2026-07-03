//! システム UI 共通のテーマ定数と egui ウィジェットヘルパー。

pub(crate) const PANEL_FILL: egui::Color32 =
    egui::Color32::from_rgba_premultiplied(12, 14, 20, 235);
pub(crate) const PANEL_STROKE: egui::Color32 = egui::Color32::from_rgb(90, 110, 150);
pub(crate) const TEXT_PRIMARY: egui::Color32 = egui::Color32::from_rgb(230, 232, 240);
pub(crate) const TEXT_MUTED: egui::Color32 = egui::Color32::from_rgb(150, 155, 170);
pub(crate) const TEXT_ERROR: egui::Color32 = egui::Color32::from_rgb(240, 110, 110);
pub(crate) const BUTTON_PRIMARY: egui::Color32 = egui::Color32::from_rgb(60, 120, 200);
pub(crate) const BUTTON_NEUTRAL: egui::Color32 = egui::Color32::from_rgb(70, 72, 82);
pub(crate) const BUTTON_DANGER: egui::Color32 = egui::Color32::from_rgb(140, 55, 55);

pub(crate) const MENU_PANEL_WIDTH: f32 = 320.0;
pub(crate) const FORM_PANEL_WIDTH: f32 = 420.0;
pub(crate) const MENU_BUTTON_SIZE: egui::Vec2 = egui::vec2(280.0, 40.0);

/// 画面全体を薄暗くするオーバーレイ。メニューがゲーム画面より前面であることを示す。
///
/// ゲーム内 Canvas UI（ダイアログ含む）は `Order::Foreground` を使うため、
/// バックドロップは `Foreground`、メニュー本体は一段上の `Tooltip` に置く。
/// 同一 Order だとバックドロップをクリックした際にレイヤーが最前面へ
/// 並べ替えられ、メニューのボタンが押せなくなるため Order を分離する。
pub(crate) fn render_backdrop(ctx: &egui::Context) {
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

pub(crate) fn panel_frame() -> egui::Frame {
    egui::Frame::new()
        .fill(PANEL_FILL)
        .inner_margin(egui::Margin::symmetric(20, 18))
        .corner_radius(10.0)
        .stroke(egui::Stroke::new(1.5, PANEL_STROKE))
}

/// 画面中央のシステム UI パネル（バックドロップ付き）。
///
/// メニュー本体はバックドロップより上の `Order::Tooltip` に置く（上記参照）。
pub(crate) fn centered_panel<R>(
    ctx: &egui::Context,
    id: &str,
    width: f32,
    add_contents: impl FnOnce(&mut egui::Ui) -> R,
) {
    render_backdrop(ctx);
    egui::Area::new(egui::Id::new(id))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Tooltip)
        .show(ctx, |ui| {
            panel_frame().show(ui, |ui| {
                ui.set_width(width);
                add_contents(ui);
            });
        });
}

pub(crate) fn menu_button(ui: &mut egui::Ui, label: &str, fill: egui::Color32) -> bool {
    ui.add(
        egui::Button::new(
            egui::RichText::new(label)
                .color(egui::Color32::WHITE)
                .strong(),
        )
        .fill(fill)
        .min_size(MENU_BUTTON_SIZE),
    )
    .clicked()
}

/// フォーム用の小型ボタン。
pub(crate) fn small_button(ui: &mut egui::Ui, label: &str, fill: egui::Color32) -> bool {
    ui.add(
        egui::Button::new(egui::RichText::new(label).color(egui::Color32::WHITE))
            .fill(fill)
            .min_size(egui::vec2(0.0, 28.0)),
    )
    .clicked()
}

/// タイトル行（タイトル + 右端の x 閉じるボタン）。閉じるが押されたら true。
pub(crate) fn title_row(ui: &mut egui::Ui, title: &str) -> bool {
    let mut close_clicked = false;
    ui.horizontal(|ui| {
        ui.label(
            egui::RichText::new(title)
                .color(TEXT_PRIMARY)
                .size(20.0)
                .strong(),
        );
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if ui
                .add(egui::Button::new(egui::RichText::new("x").strong()).fill(BUTTON_NEUTRAL))
                .clicked()
            {
                close_clicked = true;
            }
        });
    });
    close_clicked
}

/// ラベル付きテキスト入力（`password` でマスク表示）。
pub(crate) fn text_field(
    ui: &mut egui::Ui,
    label: &str,
    value: &mut String,
    password: bool,
) -> egui::Response {
    ui.label(egui::RichText::new(label).color(TEXT_PRIMARY));
    let response = ui.add(
        egui::TextEdit::singleline(value)
            .password(password)
            .desired_width(f32::INFINITY),
    );
    ui.end_row();
    response
}

/// フィールド直下の赤字エラー行（egui::Grid の行として出す）。
pub(crate) fn field_error_row(ui: &mut egui::Ui, message: &str) {
    ui.label(""); // ラベル列を空ける
    ui.label(egui::RichText::new(message).color(TEXT_ERROR).size(12.0));
    ui.end_row();
}

/// フォーム全体のエラー（赤字）。
pub(crate) fn form_error(ui: &mut egui::Ui, message: &str) {
    ui.label(egui::RichText::new(message).color(TEXT_ERROR).size(13.0));
}

/// 補足テキスト（グレー小文字）。
pub(crate) fn hint_text(ui: &mut egui::Ui, message: &str) {
    ui.label(egui::RichText::new(message).color(TEXT_MUTED).size(12.0));
}
