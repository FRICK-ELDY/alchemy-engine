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
    // trace にしておき、RUST_LOG=trace のときだけ毎フレーム出力（debug だと 60fps でコンソールが埋まる）
    log::trace!("physics_step: delta={}ms frame_id={}", delta_ms, w.frame_id);
    let t_start = std::time::Instant::now();

    w.frame_id += 1;

    let dt = delta_ms as f32 / 1000.0;

    // ── スコアポップアップの lifetime を減衰 ──────────────────────
    update_score_popups(w, dt);

    // ── 経過時間を更新 ────────────────────────────────────────────
    w.elapsed_seconds += dt;
    let dx = w.player.input_dx;
    let dy = w.player.input_dy;

    // 斜め移動を正規化して速度を一定に保つ
    let len = (dx * dx + dy * dy).sqrt();
    if len > 0.001 {
        w.player.x += (dx / len) * PLAYER_SPEED * dt;
        w.player.y += (dy / len) * PLAYER_SPEED * dt;
    }

    // プレイヤー vs 障害物（重なったら押し出し）
    obstacle_resolve::resolve_obstacles_player(
        &w.collision,
        &mut w.player.x,
        &mut w.player.y,
        &mut w.obstacle_query_buf,
    );

    w.player.x = w.player.x.clamp(0.0, MAP_WIDTH  - PLAYER_SIZE);
    w.player.y = w.player.y.clamp(0.0, MAP_HEIGHT - PLAYER_SIZE);

    // Chase AI（x86_64 では SIMD 版、それ以外は rayon 版）
    let px = w.player.x + PLAYER_RADIUS;
    let py = w.player.y + PLAYER_RADIUS;
    #[cfg(target_arch = "x86_64")]
    update_chase_ai_simd(&mut w.enemies, px, py, dt);
    #[cfg(not(target_arch = "x86_64"))]
    update_chase_ai(&mut w.enemies, px, py, dt);

    // 敵同士の重なりを解消する分離パス
    apply_separation(&mut w.enemies, ENEMY_SEPARATION_RADIUS, ENEMY_SEPARATION_FORCE, dt);

    // 敵 vs 障害物（Ghost 以外は押し出し）
    resolve_obstacles_enemy(w);

    // ── 衝突判定（Spatial Hash）──────────────────────────────────
    // 1. 動的 Spatial Hash を再構築
    w.rebuild_collision();

    // 無敵タイマーを更新
    if w.player.invincible_timer > 0.0 {
        w.player.invincible_timer = (w.player.invincible_timer - dt).max(0.0);
    }

    // 2. プレイヤー周辺の敵を取得して円-円判定
    // 最大の敵半径（Golem: 32px）を考慮してクエリ半径を広げる
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
            // HP の権威は Elixir 側。ここではイベント発行のみ行い、
            // Elixir が PlayerDamaged を受信して player_hp を減算し、
            // 次フレームで set_player_hp NIF で注入する。
            if w.player.invincible_timer <= 0.0 && w.player.hp > 0.0 {
                let dmg = params.damage_per_sec * dt;
                w.player.invincible_timer = INVINCIBLE_DURATION;
                w.frame_events.push(FrameEvent::PlayerDamaged { damage: dmg });
                // 赤いパーティクルをプレイヤー位置に発生
                let ppx = w.player.x + PLAYER_RADIUS;
                let ppy = w.player.y + PLAYER_RADIUS;
                w.particles.emit(ppx, ppy, 6, [1.0, 0.15, 0.15, 1.0]);
            }
        }
    }

    // ── 武器スロット発射処理 ──────────────────────────────────────
    update_weapon_attacks(w, dt, px, py);

    // ── パーティクル更新: 移動 + 重力 + フェードアウト ───────────
    update_particles(w, dt);

    // ── アイテム更新（磁石エフェクト + 自動収集） ────────────────
    update_items(w, dt, px, py);

    // ── 弾丸移動 + 弾丸 vs 敵衝突判定 ───────────────────────────
    update_projectiles_and_enemy_hits(w, dt);

    // ── ボス更新 ─────────────────────────────────────────────────
    update_boss(w, dt);

    // ── フレーム時間計測 ──────────────────────────────────────────
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
