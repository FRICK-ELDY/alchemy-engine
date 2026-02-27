use super::{GamePhase, GameUiState, HudData};
use game_core::weapon::weapon_upgrade_desc;

/// HUD を描画し、ボタン操作があった場合はアクション文字列を返す。
/// - レベルアップ選択: 武器名
/// - タイトル画面「Start」: "__start__"
/// - ゲームオーバー「Retry」: "__retry__"
/// - 1.5.3: セーブ「__save__」/ ロード「__load__」/ ロード確認「__load_confirm__」「__load_cancel__」
pub fn build_hud_ui(ctx: &egui::Context, hud: &HudData, fps: f32, ui_state: &mut GameUiState) -> Option<String> {
    // トースト更新（毎フレーム減衰）
    if let Some((_, ref mut t)) = ui_state.save_toast {
        *t -= ctx.input(|i| i.stable_dt);
        if *t <= 0.0 {
            ui_state.save_toast = None;
        }
    }

    let mut chosen = match hud.phase {
        GamePhase::Title    => build_title_ui(ctx),
        GamePhase::GameOver => build_game_over_ui(ctx, hud),
        GamePhase::Playing  => build_playing_ui(ctx, hud, fps, ui_state),
    };

    // ロードダイアログ（モーダル）
    if ui_state.load_dialog.is_some() {
        if let Some(dialog_result) = build_load_dialog(ctx, ui_state) {
            chosen = Some(dialog_result);
        }
    }

    // pending_action（Save/Load ボタン）を優先
    if let Some(action) = ui_state.pending_action.take() {
        chosen = Some(action);
    }

    // セーブトースト表示
    if let Some((ref msg, _)) = ui_state.save_toast {
        build_save_toast(ctx, msg);
    }

    chosen
}

/// タイトル画面（操作説明 + START ボタン）
fn build_title_ui(ctx: &egui::Context) -> Option<String> {
    let mut chosen = None;
    egui::Area::new(egui::Id::new("title"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(5, 5, 20, 230))
                .inner_margin(egui::Margin::symmetric(60, 40))
                .corner_radius(16.0)
                .stroke(egui::Stroke::new(2.0, egui::Color32::from_rgb(100, 160, 255)))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(
                            egui::RichText::new("Elixir x Rust Survivor")
                                .color(egui::Color32::from_rgb(120, 200, 255))
                                .size(36.0)
                                .strong(),
                        );
                        ui.add_space(8.0);
                        ui.label(
                            egui::RichText::new("Survive as long as possible!")
                                .color(egui::Color32::from_rgb(180, 200, 220))
                                .size(16.0),
                        );
                        ui.add_space(4.0);
                        for line in &[
                            "WASD / Arrow Keys: Move",
                            "1/2/3: Choose weapon on level up",
                            "Esc: Skip level up",
                        ] {
                            ui.label(
                                egui::RichText::new(*line)
                                    .color(egui::Color32::from_rgb(150, 170, 190))
                                    .size(13.0),
                            );
                        }
                        ui.add_space(24.0);
                        let btn = egui::Button::new(
                            egui::RichText::new("  START GAME  ").size(22.0).strong(),
                        )
                        .fill(egui::Color32::from_rgb(40, 100, 200))
                        .min_size(egui::vec2(200.0, 50.0));
                        if ui.add(btn).clicked() {
                            chosen = Some("__start__".to_string());
                        }
                    });
                });
        });
    chosen
}

/// ゲームオーバー画面（スコア・生存時間・撃破数 + RETRY ボタン）
fn build_game_over_ui(ctx: &egui::Context, hud: &HudData) -> Option<String> {
    let mut chosen = None;
    egui::Area::new(egui::Id::new("gameover"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(20, 5, 5, 235))
                .inner_margin(egui::Margin::symmetric(50, 35))
                .corner_radius(16.0)
                .stroke(egui::Stroke::new(2.0, egui::Color32::from_rgb(200, 60, 60)))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(
                            egui::RichText::new("GAME OVER")
                                .color(egui::Color32::from_rgb(255, 80, 80))
                                .size(40.0)
                                .strong(),
                        );
                        ui.add_space(16.0);
                        let total_s = hud.elapsed_seconds as u32;
                        let (m, s) = (total_s / 60, total_s % 60);
                        for (text, color) in &[
                            (format!("Survived:  {:02}:{:02}", m, s), egui::Color32::from_rgb(220, 220, 255)),
                            (format!("Score:     {}", hud.score),     egui::Color32::from_rgb(255, 220, 80)),
                            (format!("Kills:     {}", hud.kill_count), egui::Color32::from_rgb(200, 230, 200)),
                            (format!("Level:     {}", hud.level),     egui::Color32::from_rgb(180, 200, 255)),
                        ] {
                            ui.label(egui::RichText::new(text).color(*color).size(18.0));
                        }
                        ui.add_space(20.0);
                        let btn = egui::Button::new(
                            egui::RichText::new("  RETRY  ").size(20.0).strong(),
                        )
                        .fill(egui::Color32::from_rgb(160, 40, 40))
                        .min_size(egui::vec2(160.0, 44.0));
                        if ui.add(btn).clicked() {
                            chosen = Some("__retry__".to_string());
                        }
                    });
                });
        });
    chosen
}

/// 1.5.3: ロード確認ダイアログ
fn build_load_dialog(ctx: &egui::Context, ui_state: &mut GameUiState) -> Option<String> {
    let dialog_type = ui_state.load_dialog?;
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
                .stroke(egui::Stroke::new(2.0, egui::Color32::from_rgb(100, 180, 255)))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        if dialog_type {
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
                                if ui.add(
                                    egui::Button::new(egui::RichText::new("Load").color(egui::Color32::WHITE))
                                        .fill(egui::Color32::from_rgb(60, 120, 200))
                                        .min_size(egui::vec2(100.0, 36.0)),
                                ).clicked() {
                                    result = Some("__load_confirm__".to_string());
                                }
                                if ui.add(
                                    egui::Button::new(egui::RichText::new("Cancel").color(egui::Color32::WHITE))
                                        .fill(egui::Color32::from_rgb(80, 80, 80))
                                        .min_size(egui::vec2(100.0, 36.0)),
                                ).clicked() {
                                    result = Some("__load_cancel__".to_string());
                                }
                            });
                        } else {
                            ui.label(
                                egui::RichText::new("No save data")
                                    .color(egui::Color32::from_rgb(255, 200, 100))
                                    .size(20.0)
                                    .strong(),
                            );
                            ui.add_space(20.0);
                            if ui.add(
                                egui::Button::new(egui::RichText::new("OK").color(egui::Color32::WHITE))
                                    .fill(egui::Color32::from_rgb(80, 80, 80))
                                    .min_size(egui::vec2(100.0, 36.0)),
                            ).clicked() {
                                result = Some("__load_cancel__".to_string());
                            }
                        }
                    });
                });
        });

    result
}

/// 1.5.3: セーブトースト（画面上部中央に数秒表示）
fn build_save_toast(ctx: &egui::Context, msg: &str) {
    egui::Area::new(egui::Id::new("save_toast"))
        .anchor(egui::Align2::CENTER_TOP, egui::vec2(0.0, 80.0))
        .order(egui::Order::Tooltip)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(20, 80, 20, 230))
                .inner_margin(egui::Margin::symmetric(24, 12))
                .corner_radius(8.0)
                .stroke(egui::Stroke::new(1.0, egui::Color32::from_rgb(100, 255, 100)))
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

/// プレイ中の全 HUD（フラッシュ・ポップアップ・ステータスバー・ボス HP・レベルアップ・セーブ/ロード）
fn build_playing_ui(ctx: &egui::Context, hud: &HudData, fps: f32, ui_state: &mut GameUiState) -> Option<String> {
    build_screen_flash_ui(ctx, hud);
    build_score_popups_ui(ctx, hud);
    build_playing_hud_ui(ctx, hud, fps, ui_state);
    build_boss_hp_bar_ui(ctx, hud);
    build_level_up_ui(ctx, hud)
}

/// 画面フラッシュ（プレイヤーダメージ時に赤いオーバーレイ）
fn build_screen_flash_ui(ctx: &egui::Context, hud: &HudData) {
    if hud.screen_flash_alpha <= 0.0 { return; }
    let alpha = (hud.screen_flash_alpha * 255.0) as u8;
    egui::Area::new(egui::Id::new("screen_flash"))
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .order(egui::Order::Background)
        .show(ctx, |ui| {
            let screen_rect = ui.ctx().screen_rect();
            ui.painter().rect_filled(
                screen_rect,
                0.0,
                egui::Color32::from_rgba_unmultiplied(200, 30, 30, alpha),
            );
        });
}

/// スコアポップアップ（ワールド座標 → スクリーン座標変換して描画）
fn build_score_popups_ui(ctx: &egui::Context, hud: &HudData) {
    if hud.score_popups.is_empty() { return; }
    egui::Area::new(egui::Id::new("score_popups"))
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            let painter = ui.painter();
            for &(wx, wy, value, lifetime) in &hud.score_popups {
                let sx = wx - hud.camera_x;
                let sy = wy - hud.camera_y;
                let alpha = (lifetime / 0.8).clamp(0.0, 1.0);
                let color = egui::Color32::from_rgba_unmultiplied(
                    255, 230, 50, (alpha * 220.0) as u8,
                );
                painter.text(
                    egui::pos2(sx, sy),
                    egui::Align2::CENTER_CENTER,
                    format!("+{}", value),
                    egui::FontId::proportional(14.0),
                    color,
                );
            }
        });
}

/// 上部ステータスバー（HP・EXP・スコア・タイマー・武器）と右上デバッグ情報
fn build_playing_hud_ui(ctx: &egui::Context, hud: &HudData, fps: f32, ui_state: &mut GameUiState) -> Option<String> {
    // 上部 HUD バー
    egui::Area::new(egui::Id::new("hud_top"))
        .anchor(egui::Align2::LEFT_TOP, egui::vec2(8.0, 8.0))
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(0, 0, 0, 180))
                .inner_margin(egui::Margin::symmetric(12, 8))
                .corner_radius(6.0)
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        // HP バー
                        let hp_ratio = if hud.max_hp > 0.0 {
                            (hud.hp / hud.max_hp).clamp(0.0, 1.0)
                        } else {
                            0.0
                        };
                        ui.label(
                            egui::RichText::new("HP")
                                .color(egui::Color32::from_rgb(255, 100, 100))
                                .strong(),
                        );
                        let (rect, _) = ui.allocate_exact_size(
                            egui::vec2(160.0, 18.0),
                            egui::Sense::hover(),
                        );
                        let painter = ui.painter();
                        painter.rect_filled(rect, 4.0, egui::Color32::from_rgb(60, 20, 20));
                        let fill_w = rect.width() * hp_ratio;
                        let fill_rect = egui::Rect::from_min_size(
                            rect.min,
                            egui::vec2(fill_w, rect.height()),
                        );
                        let hp_color = if hp_ratio > 0.5 {
                            egui::Color32::from_rgb(80, 220, 80)
                        } else if hp_ratio > 0.25 {
                            egui::Color32::from_rgb(220, 180, 0)
                        } else {
                            egui::Color32::from_rgb(220, 60, 60)
                        };
                        painter.rect_filled(fill_rect, 4.0, hp_color);
                        ui.label(
                            egui::RichText::new(format!("{:.0}/{:.0}", hud.hp, hud.max_hp))
                                .color(egui::Color32::WHITE),
                        );

                        ui.separator();

                        // EXP バー
                        let exp_total = hud.exp + hud.exp_to_next;
                        let exp_ratio = if exp_total > 0 {
                            (hud.exp as f32 / exp_total as f32).clamp(0.0, 1.0)
                        } else {
                            0.0
                        };
                        ui.label(
                            egui::RichText::new(format!("Lv.{}", hud.level))
                                .color(egui::Color32::from_rgb(255, 220, 50))
                                .strong(),
                        );
                        let (exp_rect, _) = ui.allocate_exact_size(
                            egui::vec2(100.0, 18.0),
                            egui::Sense::hover(),
                        );
                        let painter = ui.painter();
                        painter.rect_filled(exp_rect, 4.0, egui::Color32::from_rgb(20, 20, 60));
                        let exp_fill = egui::Rect::from_min_size(
                            exp_rect.min,
                            egui::vec2(exp_rect.width() * exp_ratio, exp_rect.height()),
                        );
                        painter.rect_filled(exp_fill, 4.0, egui::Color32::from_rgb(80, 120, 255));
                        ui.label(
                            egui::RichText::new(format!("EXP {}", hud.exp))
                                .color(egui::Color32::from_rgb(180, 200, 255)),
                        );

                        ui.separator();

                        // スコア・タイマー
                        let total_s = hud.elapsed_seconds as u32;
                        let (m, s) = (total_s / 60, total_s % 60);
                        ui.label(
                            egui::RichText::new(format!("Score: {}", hud.score))
                                .color(egui::Color32::from_rgb(255, 220, 100))
                                .strong(),
                        );
                        ui.label(
                            egui::RichText::new(format!("{:02}:{:02}", m, s))
                                .color(egui::Color32::WHITE),
                        );

                        // 武器スロット
                        if !hud.weapon_levels.is_empty() {
                            ui.separator();
                            for (name, lv) in &hud.weapon_levels {
                                ui.label(
                                    egui::RichText::new(format!("[{}] Lv.{lv}", weapon_short_name(name)))
                                        .color(egui::Color32::from_rgb(180, 230, 255))
                                        .strong(),
                                );
                            }
                        }

                        // 1.5.3: セーブ・ロードボタン
                        ui.separator();
                        if ui.add(
                            egui::Button::new(egui::RichText::new("Save").color(egui::Color32::from_rgb(100, 220, 100)))
                                .min_size(egui::vec2(50.0, 22.0)),
                        ).clicked() {
                            ui_state.pending_action = Some("__save__".to_string());
                        }
                        if ui.add(
                            egui::Button::new(egui::RichText::new("Load").color(egui::Color32::from_rgb(100, 180, 255)))
                                .min_size(egui::vec2(50.0, 22.0)),
                        ).clicked() {
                            ui_state.pending_action = Some("__load__".to_string());
                        }
                    });
                });
        });

    // 右上: デバッグ情報
    egui::Area::new(egui::Id::new("hud_debug"))
        .anchor(egui::Align2::RIGHT_TOP, egui::vec2(-8.0, 8.0))
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(0, 0, 0, 140))
                .inner_margin(egui::Margin::symmetric(8, 6))
                .corner_radius(6.0)
                .show(ui, |ui| {
                    ui.label(
                        egui::RichText::new(format!("FPS: {fps:.0}"))
                            .color(egui::Color32::from_rgb(100, 255, 100)),
                    );
                    ui.label(
                        egui::RichText::new(format!("Enemies: {}", hud.enemy_count))
                            .color(egui::Color32::from_rgb(255, 150, 100)),
                    );
                    ui.label(
                        egui::RichText::new(format!("Bullets: {}", hud.bullet_count))
                            .color(egui::Color32::from_rgb(200, 200, 255)),
                    );
                    ui.label(
                        egui::RichText::new(format!("Items: {}", hud.item_count))
                            .color(egui::Color32::from_rgb(150, 230, 150)),
                    );
                    ui.label(
                        egui::RichText::new(format!("Cam: ({:.0}, {:.0})", hud.camera_x, hud.camera_y))
                            .color(egui::Color32::from_rgb(180, 180, 255)),
                    );
                    if hud.magnet_timer > 0.0 {
                        ui.label(
                            egui::RichText::new(format!("MAGNET {:.1}s", hud.magnet_timer))
                                .color(egui::Color32::from_rgb(255, 230, 50))
                                .strong(),
                        );
                    }
                });
        });

    None
}

/// ボス HP バー（画面上部中央）
fn build_boss_hp_bar_ui(ctx: &egui::Context, hud: &HudData) {
    let Some(ref boss) = hud.boss_info else { return };
    let boss_ratio = if boss.max_hp > 0.0 {
        (boss.hp / boss.max_hp).clamp(0.0, 1.0)
    } else {
        0.0
    };
    egui::Area::new(egui::Id::new("boss_hp_bar"))
        .anchor(egui::Align2::CENTER_TOP, egui::vec2(0.0, 8.0))
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(20, 0, 30, 220))
                .inner_margin(egui::Margin::symmetric(16, 10))
                .corner_radius(8.0)
                .stroke(egui::Stroke::new(2.0, egui::Color32::from_rgb(200, 0, 255)))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(
                            egui::RichText::new(format!("👹 {}", boss.name))
                                .color(egui::Color32::from_rgb(255, 80, 80))
                                .size(18.0)
                                .strong(),
                        );
                        ui.add_space(4.0);
                        let (bar_rect, _) = ui.allocate_exact_size(
                            egui::vec2(360.0, 22.0),
                            egui::Sense::hover(),
                        );
                        let painter = ui.painter();
                        painter.rect_filled(bar_rect, 6.0, egui::Color32::from_rgb(40, 10, 10));
                        let fill_w = bar_rect.width() * boss_ratio;
                        let fill_rect = egui::Rect::from_min_size(
                            bar_rect.min,
                            egui::vec2(fill_w, bar_rect.height()),
                        );
                        let bar_color = if boss_ratio > 0.5 {
                            egui::Color32::from_rgb(180, 0, 220)
                        } else if boss_ratio > 0.25 {
                            egui::Color32::from_rgb(220, 60, 60)
                        } else {
                            egui::Color32::from_rgb(255, 30, 30)
                        };
                        painter.rect_filled(fill_rect, 6.0, bar_color);
                        ui.label(
                            egui::RichText::new(format!("{:.0} / {:.0}", boss.hp, boss.max_hp))
                                .color(egui::Color32::from_rgb(255, 200, 255))
                                .size(12.0),
                        );
                    });
                });
        });
}

/// レベルアップ選択画面
fn build_level_up_ui(ctx: &egui::Context, hud: &HudData) -> Option<String> {
    if !hud.level_up_pending { return None; }

    // キーボードショートカット（Esc / 1 / 2 / 3）
    if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
        return Some("__skip__".to_string());
    }
    if !hud.weapon_choices.is_empty() {
        let selected_index = ctx.input(|i| {
            if i.key_pressed(egui::Key::Num1) { Some(0usize) }
            else if i.key_pressed(egui::Key::Num2) { Some(1usize) }
            else if i.key_pressed(egui::Key::Num3) { Some(2usize) }
            else { None }
        });
        if let Some(idx) = selected_index {
            if let Some(choice) = hud.weapon_choices.get(idx) {
                return Some(choice.clone());
            }
        }
    }

    let mut chosen = None;
    egui::Area::new(egui::Id::new("level_up"))
        .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
        .order(egui::Order::Foreground)
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(10, 10, 40, 240))
                .inner_margin(egui::Margin::symmetric(40, 30))
                .corner_radius(12.0)
                .stroke(egui::Stroke::new(2.0, egui::Color32::from_rgb(255, 220, 50)))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(
                            egui::RichText::new(format!("*** LEVEL UP!  Lv.{} ***", hud.level))
                                .color(egui::Color32::from_rgb(255, 220, 50))
                                .size(28.0)
                                .strong(),
                        );
                        ui.add_space(8.0);
                        let result = if hud.weapon_choices.is_empty() {
                            build_max_level_ui(ui)
                        } else {
                            build_weapon_choice_ui(ui, hud)
                        };
                        if result.is_some() {
                            chosen = result;
                        }
                    });
                });
        });
    chosen
}

/// 全武器がMaxLvの場合のUI（「Continue [Esc]」ボタンのみ）
fn build_max_level_ui(ui: &mut egui::Ui) -> Option<String> {
    ui.label(
        egui::RichText::new("All weapons are at MAX level!")
            .color(egui::Color32::from_rgb(255, 180, 50))
            .size(16.0)
            .strong(),
    );
    ui.add_space(16.0);
    let btn = egui::Button::new(
        egui::RichText::new("Continue  [Esc]")
            .size(16.0)
            .strong(),
    )
    .fill(egui::Color32::from_rgb(80, 80, 80))
    .min_size(egui::vec2(160.0, 36.0));
    if ui.add(btn).clicked() {
        Some("__skip__".to_string())
    } else {
        None
    }
}

/// 武器選択肢がある場合のUI（武器カード × N + 「Skip [Esc]」ボタン）
fn build_weapon_choice_ui(ui: &mut egui::Ui, hud: &HudData) -> Option<String> {
    let mut chosen: Option<String> = None;

    ui.label(
        egui::RichText::new("Choose a weapon")
            .color(egui::Color32::WHITE)
            .size(16.0),
    );
    ui.add_space(16.0);

    ui.horizontal(|ui| {
        for choice in &hud.weapon_choices {
            let current_lv = hud.weapon_levels
                .iter()
                .find(|(n, _)| n == choice)
                .map(|(_, lv)| *lv)
                .unwrap_or(0);
            if build_weapon_card(ui, choice, current_lv).is_some() {
                chosen = Some(choice.clone());
            }
            ui.add_space(12.0);
        }
    });

    ui.add_space(12.0);
    let skip_btn = egui::Button::new(
        egui::RichText::new("Skip  [Esc]").size(12.0),
    )
    .fill(egui::Color32::from_rgba_unmultiplied(60, 60, 60, 200))
    .min_size(egui::vec2(90.0, 24.0));
    if ui.add(skip_btn).clicked() {
        chosen = Some("__skip__".to_string());
    }

    chosen
}

/// 武器1枚分のカードUIを描画し、選択されたら `Some(())` を返す
fn build_weapon_card(ui: &mut egui::Ui, choice: &str, current_lv: u32) -> Option<()> {
    let is_upgrade  = current_lv > 0;
    let next_lv     = current_lv + 1;

    let border_color = if is_upgrade {
        egui::Color32::from_rgb(255, 180, 50)
    } else {
        egui::Color32::from_rgb(100, 180, 255)
    };
    let bg_color = if is_upgrade {
        egui::Color32::from_rgb(50, 35, 10)
    } else {
        egui::Color32::from_rgb(15, 30, 60)
    };

    let frame = egui::Frame::new()
        .fill(bg_color)
        .inner_margin(egui::Margin::symmetric(16, 14))
        .corner_radius(10.0)
        .stroke(egui::Stroke::new(2.0, border_color));

    let response = frame.show(ui, |ui| {
        ui.set_min_width(140.0);
        ui.vertical_centered(|ui| {
            ui.label(
                egui::RichText::new(weapon_short_name(choice))
                    .color(egui::Color32::from_rgb(220, 230, 255))
                    .size(16.0)
                    .strong(),
            );
            ui.add_space(4.0);

            let lv_text = if is_upgrade {
                format!("Lv.{current_lv} -> Lv.{next_lv}")
            } else {
                "NEW!".to_string()
            };
            let lv_color = if is_upgrade {
                egui::Color32::from_rgb(255, 200, 80)
            } else {
                egui::Color32::from_rgb(100, 255, 150)
            };
            ui.label(
                egui::RichText::new(lv_text)
                    .color(lv_color)
                    .size(13.0)
                    .strong(),
            );
            ui.add_space(6.0);

            for line in weapon_upgrade_desc(choice, current_lv) {
                ui.label(
                    egui::RichText::new(line)
                        .color(egui::Color32::from_rgb(180, 200, 180))
                        .size(11.0),
                );
            }
            ui.add_space(8.0);

            let btn = egui::Button::new(
                egui::RichText::new("Select  [1/2/3]")
                    .size(13.0)
                    .strong(),
            )
            .fill(border_color)
            .min_size(egui::vec2(110.0, 28.0));
            ui.add(btn)
        }).inner
    });

    if response.inner.clicked() { Some(()) } else { None }
}

fn weapon_short_name(name: &str) -> &str {
    match name {
        "magic_wand" => "Magic Wand",
        "axe"        => "Axe",
        "cross"      => "Cross",
        "whip"       => "Whip",
        "fireball"   => "Fireball",
        "lightning"  => "Lightning",
        _            => name,
    }
}
