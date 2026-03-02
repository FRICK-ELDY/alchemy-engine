//! Path: native/game_nif/src/render_snapshot.rs
//! Summary: GameWorld から描画用スナップショットを構築

use game_physics::constants::{INVINCIBLE_DURATION, PLAYER_SIZE, SCREEN_HEIGHT, SCREEN_WIDTH};
use game_physics::weapon::weapon_upgrade_desc;
use game_physics::world::GameWorldInner;
use game_render::{BossHudInfo, CameraParams, DrawCommand, GamePhase, HudData, RenderFrame};

/// `GameWorldInner` から `RenderFrame` を構築する。
/// Phase R-2 以降でこの関数は Elixir 側（game_content）に移行する。
pub fn build_render_frame(w: &GameWorldInner) -> RenderFrame {
    let anim_frame = ((w.frame_id / 4) % 4) as u8;
    // alive フラグで絞り込まれるため実際の push 数より多い場合があるが、
    // 上限見積もりとして過剰確保しておき再アロケーションを避ける。
    let mut commands = Vec::with_capacity(
        1 + w.boss.is_some() as usize
            + w.enemies.count
            + w.bullets.count
            + w.particles.count
            + w.items.count
            + w.collision.obstacles.len(),
    );

    commands.push(DrawCommand::PlayerSprite {
        x: w.player.x,
        y: w.player.y,
        frame: anim_frame,
    });

    if let Some(ref boss) = w.boss {
        let boss_sprite_size = boss.radius * 2.0;
        commands.push(DrawCommand::Sprite {
            x: boss.x - boss_sprite_size / 2.0,
            y: boss.y - boss_sprite_size / 2.0,
            kind_id: boss.render_kind,
            frame: 0,
        });
    }

    for i in 0..w.enemies.len() {
        if w.enemies.alive[i] != 0 {
            let base_kind = w
                .params
                .enemies
                .get(w.enemies.kind_ids[i] as usize)
                .map(|ep| ep.render_kind)
                .unwrap_or(1);
            commands.push(DrawCommand::Sprite {
                x: w.enemies.positions_x[i],
                y: w.enemies.positions_y[i],
                kind_id: base_kind,
                frame: anim_frame,
            });
        }
    }

    for i in 0..w.bullets.len() {
        if w.bullets.alive[i] {
            commands.push(DrawCommand::Sprite {
                x: w.bullets.positions_x[i],
                y: w.bullets.positions_y[i],
                kind_id: w.bullets.render_kind[i],
                frame: 0,
            });
        }
    }

    for i in 0..w.particles.len() {
        if !w.particles.alive[i] {
            continue;
        }
        let alpha = (w.particles.lifetime[i] / w.particles.max_lifetime[i]).clamp(0.0, 1.0);
        let c = w.particles.color[i];
        commands.push(DrawCommand::Particle {
            x: w.particles.positions_x[i],
            y: w.particles.positions_y[i],
            r: c[0],
            g: c[1],
            b: c[2],
            alpha,
            size: w.particles.size[i],
        });
    }

    for i in 0..w.items.len() {
        if w.items.alive[i] {
            commands.push(DrawCommand::Item {
                x: w.items.positions_x[i],
                y: w.items.positions_y[i],
                kind: w.items.kinds[i].render_kind(),
            });
        }
    }

    for o in &w.collision.obstacles {
        commands.push(DrawCommand::Obstacle {
            x: o.x,
            y: o.y,
            radius: o.radius,
            kind: o.kind,
        });
    }

    let cam_x = w.player.x + PLAYER_SIZE / 2.0 - SCREEN_WIDTH / 2.0;
    let cam_y = w.player.y + PLAYER_SIZE / 2.0 - SCREEN_HEIGHT / 2.0;

    let boss_info = w.boss.as_ref().map(|b| BossHudInfo {
        name: "Boss".to_string(),
        hp: b.hp,
        max_hp: b.max_hp,
    });

    let weapon_levels: Vec<(String, u32)> = w
        .weapon_slots
        .iter()
        .map(|s| (format!("weapon_{}", s.kind_id), s.level))
        .collect();

    // weapon_choices の各武器名に対応する weapon_id を weapon_slots から逆引きし、
    // EntityParamTables を使ってアップグレード説明文を事前生成する。
    // weapon_slots に存在しない武器（新規取得候補）は current_lv = 0 として扱う。
    let weapon_upgrade_descs: Vec<Vec<String>> = w
        .hud_weapon_choices
        .iter()
        .map(|choice| {
            let kind_id_opt = choice
                .strip_prefix("weapon_")
                .and_then(|s| s.parse::<u8>().ok());
            match kind_id_opt {
                Some(kind_id) => {
                    let current_lv = w
                        .weapon_slots
                        .iter()
                        .find(|s| s.kind_id == kind_id)
                        .map(|s| s.level)
                        .unwrap_or(0);
                    weapon_upgrade_desc(kind_id, current_lv, &w.params)
                }
                None => vec!["Upgrade weapon".to_string()],
            }
        })
        .collect();

    let screen_flash_alpha = if w.player.invincible_timer > 0.0 && INVINCIBLE_DURATION > 0.0 {
        ((w.player.invincible_timer / INVINCIBLE_DURATION).clamp(0.0, 1.0)) * 0.5
    } else {
        0.0
    };

    let hud = HudData {
        hp: w.player.hp,
        max_hp: w.player_max_hp,
        score: w.score,
        elapsed_seconds: w.elapsed_seconds,
        level: w.hud_level,
        exp: w.hud_exp,
        exp_to_next: w.hud_exp_to_next,
        enemy_count: w.enemies.count,
        bullet_count: w.bullets.count,
        fps: 0.0,
        level_up_pending: w.hud_level_up_pending,
        weapon_choices: w.hud_weapon_choices.clone(),
        weapon_upgrade_descs,
        weapon_levels,
        magnet_timer: w.magnet_timer,
        item_count: w.items.count,
        boss_info,
        phase: GamePhase::Playing,
        screen_flash_alpha,
        score_popups: w.score_popups.clone(),
        kill_count: w.kill_count,
    };

    RenderFrame {
        commands,
        camera: CameraParams::Camera2D {
            offset_x: cam_x,
            offset_y: cam_y,
        },
        hud,
    }
}

pub struct InterpolationData {
    pub prev_player_x: f32,
    pub prev_player_y: f32,
    pub curr_player_x: f32,
    pub curr_player_y: f32,
    pub prev_tick_ms: u64,
    pub curr_tick_ms: u64,
}

pub fn copy_interpolation_data(w: &GameWorldInner) -> InterpolationData {
    InterpolationData {
        prev_player_x: w.prev_player_x,
        prev_player_y: w.prev_player_y,
        curr_player_x: w.player.x,
        curr_player_y: w.player.y,
        prev_tick_ms: w.prev_tick_ms,
        curr_tick_ms: w.curr_tick_ms,
    }
}

pub fn calc_interpolation_alpha(data: &InterpolationData, now_ms: u64) -> f32 {
    let tick_duration = data.curr_tick_ms.saturating_sub(data.prev_tick_ms);
    if tick_duration == 0 {
        return 1.0;
    }
    let elapsed = now_ms.saturating_sub(data.prev_tick_ms);
    (elapsed as f32 / tick_duration as f32).clamp(0.0, 1.0)
}

pub fn interpolate_player_pos(data: &InterpolationData, alpha: f32) -> (f32, f32) {
    let x = data.prev_player_x + (data.curr_player_x - data.prev_player_x) * alpha;
    let y = data.prev_player_y + (data.curr_player_y - data.prev_player_y) * alpha;
    (x, y)
}
