//! Path: native/game_simulation/src/game_logic/physics_step.rs
//! Summary: 物理ステップ内部実装

#[cfg(not(target_arch = "x86_64"))]
use super::chase_ai::update_chase_ai;
#[cfg(target_arch = "x86_64")]
use super::chase_ai::update_chase_ai_simd;
use super::systems::boss::update_boss;
use super::systems::collision::resolve_obstacles_enemy;
use super::systems::effects::{update_particles, update_score_popups};
use super::systems::items::update_items;
use super::systems::projectiles::update_projectiles_and_enemy_hits;
use super::systems::weapons::update_weapon_attacks;
use crate::world::{FrameEvent, GameWorldInner};
use crate::constants::{
    ENEMY_SEPARATION_FORCE, ENEMY_SEPARATION_RADIUS, FRAME_BUDGET_MS, INVINCIBLE_DURATION,
    MAP_HEIGHT, MAP_WIDTH, PLAYER_RADIUS, PLAYER_SIZE, PLAYER_SPEED,
};
use crate::entity_params::EnemyParams;
use crate::physics::obstacle_resolve;
use crate::physics::separation::apply_separation;

/// 物理ステップの内部実装（NIF と Rust ゲームループスレッドの両方から呼ぶ）
pub fn physics_step_inner(w: &mut GameWorldInner, delta_ms: f64) {
    log::trace!("physics_step: delta={}ms frame_id={}", delta_ms, w.frame_id);
    let t_start = std::time::Instant::now();

    w.frame_id += 1;

    let dt = delta_ms as f32 / 1000.0;

    update_score_popups(w, dt);

    w.elapsed_seconds += dt;
    let dx = w.player.input_dx;
    let dy = w.player.input_dy;

    let len = (dx * dx + dy * dy).sqrt();
    if len > 0.001 {
        w.player.x += (dx / len) * PLAYER_SPEED * dt;
        w.player.y += (dy / len) * PLAYER_SPEED * dt;
    }

    obstacle_resolve::resolve_obstacles_player(
        &w.collision,
        &mut w.player.x,
        &mut w.player.y,
        &mut w.obstacle_query_buf,
    );

    w.player.x = w.player.x.clamp(0.0, MAP_WIDTH  - PLAYER_SIZE);
    w.player.y = w.player.y.clamp(0.0, MAP_HEIGHT - PLAYER_SIZE);

    let px = w.player.x + PLAYER_RADIUS;
    let py = w.player.y + PLAYER_RADIUS;
    #[cfg(target_arch = "x86_64")]
    update_chase_ai_simd(&mut w.enemies, px, py, dt);
    #[cfg(not(target_arch = "x86_64"))]
    update_chase_ai(&mut w.enemies, px, py, dt);

    apply_separation(&mut w.enemies, ENEMY_SEPARATION_RADIUS, ENEMY_SEPARATION_FORCE, dt);

    resolve_obstacles_enemy(w);

    w.rebuild_collision();

    if w.player.invincible_timer > 0.0 {
        w.player.invincible_timer = (w.player.invincible_timer - dt).max(0.0);
    }

    let max_enemy_radius = 32.0_f32;
    let query_radius = PLAYER_RADIUS + max_enemy_radius;
    let candidates = w.collision.dynamic.query_nearby(px, py, query_radius);

    for idx in candidates {
        if !w.enemies.alive[idx] { continue; }
        let kind_id = w.enemies.kind_ids[idx];
        let params = EnemyParams::get(kind_id);
        let enemy_r = params.radius;
        let hit_radius = PLAYER_RADIUS + enemy_r;
        let ex = w.enemies.positions_x[idx] + enemy_r;
        let ey = w.enemies.positions_y[idx] + enemy_r;
        let ddx = px - ex;
        let ddy = py - ey;
        let dist_sq = ddx * ddx + ddy * ddy;

        if dist_sq < hit_radius * hit_radius {
            if w.player.invincible_timer <= 0.0 && w.player.hp > 0.0 {
                let dmg = params.damage_per_sec * dt;
                w.player.invincible_timer = INVINCIBLE_DURATION;
                w.frame_events.push(FrameEvent::PlayerDamaged { damage: dmg });
                let ppx = w.player.x + PLAYER_RADIUS;
                let ppy = w.player.y + PLAYER_RADIUS;
                w.particles.emit(ppx, ppy, 6, [1.0, 0.15, 0.15, 1.0]);
            }
        }
    }

    update_weapon_attacks(w, dt, px, py);
    update_particles(w, dt);
    update_items(w, dt, px, py);
    update_projectiles_and_enemy_hits(w, dt);
    update_boss(w, dt);

    let elapsed_ms = t_start.elapsed().as_secs_f64() * 1000.0;
    w.last_frame_time_ms = elapsed_ms;
    if elapsed_ms > FRAME_BUDGET_MS {
        eprintln!(
            "[PERF] Frame budget exceeded: {:.2}ms (enemies: {})",
            elapsed_ms,
            w.enemies.count
        );
    }
}
