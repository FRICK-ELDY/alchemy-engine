use crate::{CameraParams, UiAnchor, UiCanvas, UiComponent, UiNode, UiSize};

use super::{GameUiState, LoadDialogKind};

/// `[f32; 4]` の RGBA 値（0.0〜1.0）を egui の Color32 に変換するヘルパー。
fn to_color32(rgba: [f32; 4]) -> egui::Color32 {
    let [r, g, b, a] = rgba;
    egui::Color32::from_rgba_unmultiplied(
        (r * 255.0) as u8,
        (g * 255.0) as u8,
        (b * 255.0) as u8,
        (a * 255.0) as u8,
    )
}

fn to_color32_rgb(rgba: [f32; 4]) -> egui::Color32 {
    let [r, g, b, _] = rgba;
    egui::Color32::from_rgb((r * 255.0) as u8, (g * 255.0) as u8, (b * 255.0) as u8)
}

fn anchor_to_align2(anchor: UiAnchor) -> egui::Align2 {
    match anchor {
        UiAnchor::TopLeft => egui::Align2::LEFT_TOP,
        UiAnchor::TopCenter => egui::Align2::CENTER_TOP,
        UiAnchor::TopRight => egui::Align2::RIGHT_TOP,
        UiAnchor::MiddleLeft => egui::Align2::LEFT_CENTER,
        UiAnchor::Center => egui::Align2::CENTER_CENTER,
        UiAnchor::MiddleRight => egui::Align2::RIGHT_CENTER,
        UiAnchor::BottomLeft => egui::Align2::LEFT_BOTTOM,
        UiAnchor::BottomCenter => egui::Align2::CENTER_BOTTOM,
        UiAnchor::BottomRight => egui::Align2::RIGHT_BOTTOM,
    }
}

/// UiCanvas を描画し、ボタンが押された場合はアクション文字列を返す。
/// ui_state でセーブ/ロードダイアログ・トーストを制御する。
pub fn render_ui_canvas(
    ctx: &egui::Context,
    canvas: &UiCanvas,
    camera: &CameraParams,
    fps: f32,
    ui_state: &mut GameUiState,
) -> Option<String> {
    // トースト更新（毎フレーム減衰）
    if let Some((_, ref mut t)) = ui_state.save_toast {
        *t -= ctx.input(|i| i.stable_dt);
        if *t <= 0.0 {
            ui_state.save_toast = None;
        }
    }

    // pending_action（Save/Load ボタン）を最優先で確定させる。
    // ロードダイアログ結果より先にチェックすることで、同一フレームでの上書きを防ぐ。
    if let Some(action) = ui_state.pending_action.take() {
        let chosen = Some(action);

        // ロードダイアログが開いている場合は描画せずに閉じる。
        ui_state.load_dialog = None;

        // 各ノードを描画する。戻り値は捨てる（pending_action 優先）。
        for (idx, node) in canvas.nodes.iter().enumerate() {
            render_node(ctx, node, idx, camera, fps, ui_state);
        }
        ui_state.pending_action = None;

        if let Some((ref msg, _)) = ui_state.save_toast {
            build_save_toast(ctx, msg);
        }

        return chosen;
    }

    let mut chosen: Option<String> = None;

    for (idx, node) in canvas.nodes.iter().enumerate() {
        if let Some(action) = render_node(ctx, node, idx, camera, fps, ui_state) {
            if chosen.is_none() {
                chosen = Some(action);
            }
        }
    }

    // ロードダイアログ（モーダル）
    if ui_state.load_dialog.is_some() {
        if let Some(dialog_result) = build_load_dialog(ctx, ui_state) {
            chosen = Some(dialog_result);
        }
    }

    // セーブトースト表示
    if let Some((ref msg, _)) = ui_state.save_toast {
        build_save_toast(ctx, msg);
    }

    chosen
}

/// ノードを描画する。ボタンが押された場合はアクション文字列を返す。
/// `node_idx` は `canvas.nodes` 内のトップレベルインデックスで、
/// `egui::Area` の ID 生成に使用する（同一アンカー・オフセットのノードが複数あっても衝突しない）。
fn render_node(
    ctx: &egui::Context,
    node: &UiNode,
    node_idx: usize,
    camera: &CameraParams,
    fps: f32,
    ui_state: &mut GameUiState,
) -> Option<String> {
    match &node.component {
        UiComponent::ScreenFlash { color } => {
            render_screen_flash(ctx, *color);
            None
        }
        UiComponent::WorldText {
            world_x,
            world_y,
            world_z,
            text,
            color,
            lifetime,
            max_lifetime,
        } => {
            render_world_text(
                ctx,
                camera,
                *world_x,
                *world_y,
                *world_z,
                text,
                *color,
                *lifetime,
                *max_lifetime,
            );
            None
        }
        _ => render_node_as_area(ctx, node, node_idx, camera, fps, ui_state),
    }
}

/// egui::Area を使ってノードを描画する。`node_idx` は呼び出し元の `render_node` から渡される。
fn render_node_as_area(
    ctx: &egui::Context,
    node: &UiNode,
    node_idx: usize,
    camera: &CameraParams,
    fps: f32,
    ui_state: &mut GameUiState,
) -> Option<String> {
    let align = anchor_to_align2(node.rect.anchor);
    let offset = egui::vec2(node.rect.offset[0], node.rect.offset[1]);

    let id_str = format!("node_{node_idx}_{:?}", node.rect.anchor);

    let mut result: Option<String> = None;

    let mut area = egui::Area::new(egui::Id::new(id_str))
        .anchor(align, offset)
        .order(egui::Order::Foreground);

    if let UiSize::Fixed(w, h) = node.rect.size {
        area = area.default_size(egui::vec2(w, h));
    }

    area.show(ctx, |ui| {
        result = render_component_in_ui(ui, &node.component, &node.children, camera, fps, ui_state);
    });

    result
}

/// egui::Ui 内でコンポーネントを描画する（レイアウトコンテナ内の再帰描画でも使用）。
fn render_component_in_ui(
    ui: &mut egui::Ui,
    component: &UiComponent,
    children: &[UiNode],
    camera: &CameraParams,
    fps: f32,
    ui_state: &mut GameUiState,
) -> Option<String> {
    match component {
        UiComponent::VerticalLayout { spacing, padding } => {
            render_vertical_layout(ui, children, *spacing, *padding, camera, fps, ui_state)
        }
        UiComponent::HorizontalLayout { spacing, padding } => {
            render_horizontal_layout(ui, children, *spacing, *padding, camera, fps, ui_state)
        }
        UiComponent::Rect {
            color,
            corner_radius,
            border,
        } => render_rect_component(
            ui,
            children,
            *color,
            *corner_radius,
            *border,
            camera,
            fps,
            ui_state,
        ),
        UiComponent::Text {
            text,
            color,
            size,
            bold,
        } => {
            render_text(ui, text, *color, *size, *bold);
            None
        }
        UiComponent::Button {
            label,
            action,
            color,
            min_width,
            min_height,
        } => render_button(ui, label, action, *color, *min_width, *min_height, ui_state),
        UiComponent::ProgressBar {
            value,
            max,
            width,
            height,
            fg_color_high,
            fg_color_mid,
            fg_color_low,
            bg_color,
            corner_radius,
        } => {
            render_progress_bar(
                ui,
                *value,
                *max,
                *width,
                *height,
                *fg_color_high,
                *fg_color_mid,
                *fg_color_low,
                *bg_color,
                *corner_radius,
            );
            None
        }
        UiComponent::Separator => {
            ui.separator();
            None
        }
        UiComponent::Spacing { amount } => {
            // add_space は egui の現在のレイアウト方向に従う。
            // VerticalLayout 内では垂直スペース、HorizontalLayout 内では水平スペースとして機能する。
            ui.add_space(*amount);
            None
        }
        UiComponent::ScreenFlash { .. } | UiComponent::WorldText { .. } => {
            // これらは render_node で先に処理される
            None
        }
    }
}

/// `f32` の padding 値を `egui::Margin` の `i8` フィールドに安全に変換する。
/// `as i8` は 128.0 以上でオーバーフローするため、`clamp` で [-128, 127] に収める。
fn padding_to_margin(p: [f32; 4]) -> egui::Margin {
    egui::Margin {
        left: p[0].clamp(i8::MIN as f32, i8::MAX as f32) as i8,
        top: p[1].clamp(i8::MIN as f32, i8::MAX as f32) as i8,
        right: p[2].clamp(i8::MIN as f32, i8::MAX as f32) as i8,
        bottom: p[3].clamp(i8::MIN as f32, i8::MAX as f32) as i8,
    }
}

fn render_vertical_layout(
    ui: &mut egui::Ui,
    children: &[UiNode],
    spacing: f32,
    padding: [f32; 4],
    camera: &CameraParams,
    fps: f32,
    ui_state: &mut GameUiState,
) -> Option<String> {
    // padding: [left, top, right, bottom]
    let margin = padding_to_margin(padding);
    let mut result: Option<String> = None;
    egui::Frame::new().inner_margin(margin).show(ui, |ui| {
        ui.spacing_mut().item_spacing.y = spacing;
        ui.vertical(|ui| {
            for child in children {
                let action = render_component_in_ui(
                    ui,
                    &child.component,
                    &child.children,
                    camera,
                    fps,
                    ui_state,
                );
                if result.is_none() {
                    result = action;
                }
            }
        });
    });
    result
}

fn render_horizontal_layout(
    ui: &mut egui::Ui,
    children: &[UiNode],
    spacing: f32,
    padding: [f32; 4],
    camera: &CameraParams,
    fps: f32,
    ui_state: &mut GameUiState,
) -> Option<String> {
    // padding: [left, top, right, bottom]
    let margin = padding_to_margin(padding);
    let mut result: Option<String> = None;
    egui::Frame::new().inner_margin(margin).show(ui, |ui| {
        ui.spacing_mut().item_spacing.x = spacing;
        ui.horizontal(|ui| {
            for child in children {
                let action = render_component_in_ui(
                    ui,
                    &child.component,
                    &child.children,
                    camera,
                    fps,
                    ui_state,
                );
                if result.is_none() {
                    result = action;
                }
            }
        });
    });
    result
}

#[allow(clippy::too_many_arguments)]
fn render_rect_component(
    ui: &mut egui::Ui,
    children: &[UiNode],
    color: [f32; 4],
    corner_radius: f32,
    border: Option<([f32; 4], f32)>,
    camera: &CameraParams,
    fps: f32,
    ui_state: &mut GameUiState,
) -> Option<String> {
    let mut frame = egui::Frame::new()
        .fill(to_color32(color))
        .corner_radius(corner_radius);

    if let Some((border_color, border_width)) = border {
        frame = frame.stroke(egui::Stroke::new(
            border_width,
            to_color32_rgb(border_color),
        ));
    }

    let mut result: Option<String> = None;
    frame.show(ui, |ui| {
        for child in children {
            let action = render_component_in_ui(
                ui,
                &child.component,
                &child.children,
                camera,
                fps,
                ui_state,
            );
            if result.is_none() {
                result = action;
            }
        }
    });
    result
}

fn render_text(ui: &mut egui::Ui, text: &str, color: [f32; 4], size: f32, bold: bool) {
    let mut rich = egui::RichText::new(text)
        .color(to_color32(color))
        .size(size);
    if bold {
        rich = rich.strong();
    }
    ui.label(rich);
}

fn render_button(
    ui: &mut egui::Ui,
    label: &str,
    action: &str,
    color: [f32; 4],
    min_width: f32,
    min_height: f32,
    ui_state: &mut GameUiState,
) -> Option<String> {
    let btn = egui::Button::new(egui::RichText::new(label).strong())
        .fill(to_color32_rgb(color))
        .min_size(egui::vec2(min_width, min_height));

    if ui.add(btn).clicked() {
        // Save/Load ボタンは pending_action 経由で処理する
        match action {
            "__save__" | "__load__" => {
                ui_state.pending_action = Some(action.to_string());
                None
            }
            _ => Some(action.to_string()),
        }
    } else {
        None
    }
}

#[allow(clippy::too_many_arguments)]
fn render_progress_bar(
    ui: &mut egui::Ui,
    value: f32,
    max: f32,
    width: f32,
    height: f32,
    fg_color_high: [f32; 4],
    fg_color_mid: [f32; 4],
    fg_color_low: [f32; 4],
    bg_color: [f32; 4],
    corner_radius: f32,
) {
    let ratio = if max > 0.0 {
        (value / max).clamp(0.0, 1.0)
    } else {
        0.0
    };

    let (rect, _) = ui.allocate_exact_size(egui::vec2(width, height), egui::Sense::hover());
    let painter = ui.painter();
    painter.rect_filled(rect, corner_radius, to_color32(bg_color));

    let fill_color = if ratio > 0.5 {
        to_color32(fg_color_high)
    } else if ratio > 0.25 {
        to_color32(fg_color_mid)
    } else {
        to_color32(fg_color_low)
    };

    let fill_rect =
        egui::Rect::from_min_size(rect.min, egui::vec2(rect.width() * ratio, rect.height()));
    painter.rect_filled(fill_rect, corner_radius, fill_color);
}

fn render_screen_flash(ctx: &egui::Context, color: [f32; 4]) {
    if color[3] <= 0.0 {
        return;
    }
    egui::Area::new(egui::Id::new("screen_flash"))
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .order(egui::Order::Background)
        .show(ctx, |ui| {
            let screen_rect = ui.ctx().screen_rect();
            ui.painter()
                .rect_filled(screen_rect, 0.0, to_color32(color));
        });
}

#[allow(clippy::too_many_arguments)]
fn render_world_text(
    ctx: &egui::Context,
    camera: &CameraParams,
    world_x: f32,
    world_y: f32,
    world_z: f32,
    text: &str,
    color: [f32; 4],
    lifetime: f32,
    max_lifetime: f32,
) {
    let alpha = if max_lifetime > 0.0 {
        (lifetime / max_lifetime).clamp(0.0, 1.0)
    } else {
        1.0
    };
    let mut faded = color;
    faded[3] *= alpha;

    // lifetime をIDに含めることで、同座標に複数のポップアップが存在する場合の衝突を軽減する。
    let id_bits = ((world_x.to_bits() as u64) << 32) | (world_y.to_bits() as u64);
    let lifetime_bits = lifetime.to_bits() as u64;

    let screen_pos = match camera {
        CameraParams::Camera3D {
            eye,
            target,
            up,
            fov_deg,
            near,
            far,
        } => {
            let screen_size = ctx.screen_rect();
            let w = screen_size.width();
            let h = screen_size.height();
            if w <= 0.0 || h <= 0.0 {
                return;
            }
            let aspect = w / h;
            // MVP でワールド座標 → クリップ座標に変換
            let mvp = world_text_mvp(
                *eye,
                *target,
                *up,
                fov_deg.to_radians(),
                aspect,
                *near,
                *far,
            );
            let clip = mat4_mul_vec4(mvp, [world_x, world_y, world_z, 1.0]);
            // カメラ背後（w <= 0）は描画しない
            if clip[3] <= 0.0 {
                return;
            }
            let ndc_x = clip[0] / clip[3];
            let ndc_y = clip[1] / clip[3];
            // NDC [-1,1] → スクリーン座標
            let sx = (ndc_x + 1.0) * 0.5 * w;
            let sy = (1.0 - ndc_y) * 0.5 * h;
            egui::pos2(sx, sy)
        }
        CameraParams::Camera2D { .. } => {
            let (cam_x, cam_y) = camera.offset_xy();
            egui::pos2(world_x - cam_x, world_y - cam_y)
        }
    };

    egui::Area::new(egui::Id::new(("world_text", id_bits ^ lifetime_bits)))
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            ui.painter().text(
                screen_pos,
                egui::Align2::CENTER_CENTER,
                text,
                egui::FontId::proportional(14.0),
                to_color32(faded),
            );
        });
}

fn world_text_mvp(
    eye: [f32; 3],
    target: [f32; 3],
    up: [f32; 3],
    fov_rad: f32,
    aspect: f32,
    near: f32,
    far: f32,
) -> [[f32; 4]; 4] {
    let view = look_at_wt(eye, target, up);
    let proj = perspective_wt(fov_rad, aspect, near, far);
    mat4_mul_wt(proj, view)
}

fn mat4_mul_vec4(m: [[f32; 4]; 4], v: [f32; 4]) -> [f32; 4] {
    let mut out = [0.0f32; 4];
    for (row, out_val) in out.iter_mut().enumerate() {
        *out_val = (0..4).map(|col| m[col][row] * v[col]).sum();
    }
    out
}

fn look_at_wt(eye: [f32; 3], center: [f32; 3], up: [f32; 3]) -> [[f32; 4]; 4] {
    let f = normalize_wt(sub3_wt(center, eye));
    let r = normalize_wt(cross3_wt(f, up));
    let u = cross3_wt(r, f);
    [
        [r[0], u[0], -f[0], 0.0],
        [r[1], u[1], -f[1], 0.0],
        [r[2], u[2], -f[2], 0.0],
        [-dot3_wt(r, eye), -dot3_wt(u, eye), dot3_wt(f, eye), 1.0],
    ]
}

fn perspective_wt(fov_rad: f32, aspect: f32, near: f32, far: f32) -> [[f32; 4]; 4] {
    let tan_half = (fov_rad / 2.0).tan();
    let range = far - near;
    [
        [1.0 / (aspect * tan_half), 0.0, 0.0, 0.0],
        [0.0, 1.0 / tan_half, 0.0, 0.0],
        [0.0, 0.0, -(far + near) / range, -1.0],
        [0.0, 0.0, -2.0 * far * near / range, 0.0],
    ]
}

fn mat4_mul_wt(a: [[f32; 4]; 4], b: [[f32; 4]; 4]) -> [[f32; 4]; 4] {
    let mut out = [[0.0f32; 4]; 4];
    for col in 0..4 {
        for row in 0..4 {
            out[col][row] = (0..4).map(|k| a[k][row] * b[col][k]).sum();
        }
    }
    out
}

fn sub3_wt(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn dot3_wt(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross3_wt(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn normalize_wt(v: [f32; 3]) -> [f32; 3] {
    let len = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    if len < 1e-8 {
        return v;
    }
    [v[0] / len, v[1] / len, v[2] / len]
}

/// セーブ/ロード確認ダイアログ
fn build_load_dialog(ctx: &egui::Context, ui_state: &mut GameUiState) -> Option<String> {
    let dialog_kind = ui_state.load_dialog?;
    let mut result = None;

    egui::Area::new(egui::Id::new("load_dialog"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .interactable(true)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(0, 0, 0, 200))
                .inner_margin(egui::Margin::symmetric(40, 30))
                .corner_radius(12.0)
                .stroke(egui::Stroke::new(
                    2.0,
                    egui::Color32::from_rgb(100, 180, 255),
                ))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| match dialog_kind {
                        LoadDialogKind::Confirm => {
                            ui.label(
                                egui::RichText::new("Load saved game?")
                                    .color(egui::Color32::from_rgb(220, 220, 255))
                                    .size(20.0)
                                    .strong(),
                            );
                            ui.label(
                                egui::RichText::new("Current progress will be lost.")
                                    .color(egui::Color32::from_rgb(180, 180, 200))
                                    .size(14.0),
                            );
                            ui.add_space(20.0);
                            ui.horizontal(|ui| {
                                if ui
                                    .add(
                                        egui::Button::new(
                                            egui::RichText::new("Load").color(egui::Color32::WHITE),
                                        )
                                        .fill(egui::Color32::from_rgb(60, 120, 200))
                                        .min_size(egui::vec2(100.0, 36.0)),
                                    )
                                    .clicked()
                                {
                                    result = Some("__load_confirm__".to_string());
                                }
                                if ui
                                    .add(
                                        egui::Button::new(
                                            egui::RichText::new("Cancel")
                                                .color(egui::Color32::WHITE),
                                        )
                                        .fill(egui::Color32::from_rgb(80, 80, 80))
                                        .min_size(egui::vec2(100.0, 36.0)),
                                    )
                                    .clicked()
                                {
                                    result = Some("__load_cancel__".to_string());
                                }
                            });
                        }
                        LoadDialogKind::NoSaveData => {
                            ui.label(
                                egui::RichText::new("No save data")
                                    .color(egui::Color32::from_rgb(255, 200, 100))
                                    .size(20.0)
                                    .strong(),
                            );
                            ui.add_space(20.0);
                            if ui
                                .add(
                                    egui::Button::new(
                                        egui::RichText::new("OK").color(egui::Color32::WHITE),
                                    )
                                    .fill(egui::Color32::from_rgb(80, 80, 80))
                                    .min_size(egui::vec2(100.0, 36.0)),
                                )
                                .clicked()
                            {
                                result = Some("__load_cancel__".to_string());
                            }
                        }
                    });
                });
        });

    result
}

/// セーブトースト（画面上部中央に数秒表示）
fn build_save_toast(ctx: &egui::Context, msg: &str) {
    egui::Area::new(egui::Id::new("save_toast"))
        .anchor(egui::Align2::CENTER_TOP, egui::vec2(0.0, 80.0))
        .order(egui::Order::Tooltip)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(20, 80, 20, 230))
                .inner_margin(egui::Margin::symmetric(24, 12))
                .corner_radius(8.0)
                .stroke(egui::Stroke::new(
                    1.0,
                    egui::Color32::from_rgb(100, 255, 100),
                ))
                .show(ui, |ui| {
                    ui.label(
                        egui::RichText::new(msg)
                            .color(egui::Color32::from_rgb(200, 255, 200))
                            .size(18.0)
                            .strong(),
                    );
                });
        });
}
