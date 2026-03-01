//! Path: native/game_physics/src/game_logic/physics_step.rs
//! Summary: 物琁E��チE��プ�E部実裁E

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
    PLAYER_RADIUS, PLAYER_SIZE, PLAYER_SPEED,
};
use crate::physics::obstacle_resolve;
use crate::physics::separation::apply_separation;

/// 物琁E��チE��プ�E冁E��実裁E��EIF と Rust ゲームループスレチE��の両方から呼ぶ�E�E
pub fn physics_step_inner(w: &mut GameWorldInner, delta_ms: f64) {
    // trace にしておき、RUST_LOG=trace のときだけ毎フレーム出力！Eebug だと 60fps でコンソールが埋まる！E
    log::trace!("physics_step: delta={}ms frame_id={}", delta_ms, w.frame_id);
    let t_start = std::time::Instant::now();

    w.frame_id += 1;

    let dt = delta_ms as f32 / 1000.0;

    // ── スコアポップアチE�Eの lifetime を減衰 ──────────────────────
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

    // プレイヤー vs 障害物�E�重なったら押し�Eし！E
    obstacle_resolve::resolve_obstacles_player(
        &w.collision,
        &mut w.player.x,
        &mut w.player.y,
        &mut w.obstacle_query_buf,
    );

    w.player.x = w.player.x.clamp(0.0, w.map_width  - PLAYER_SIZE);
    w.player.y = w.player.y.clamp(0.0, w.map_height - PLAYER_SIZE);

    // Chase AI�E�E86_64 では SIMD 版、それ以外�E rayon 版！E
    let px = w.player.x + PLAYER_RADIUS;
    let py = w.player.y + PLAYER_RADIUS;
    #[cfg(target_arch = "x86_64")]
    update_chase_ai_simd(&mut w.enemies, px, py, dt);
    #[cfg(not(target_arch = "x86_64"))]
    update_chase_ai(&mut w.enemies, px, py, dt);

    // 敵同士の重なりを解消する�E離パス
    apply_separation(&mut w.enemies, ENEMY_SEPARATION_RADIUS, ENEMY_SEPARATION_FORCE, dt);

    // 敵 vs 障害物�E�Ehost 以外�E押し�Eし！E
    resolve_obstacles_enemy(w);

    // ── 衝突判定！Epatial Hash�E�──────────────────────────────────
    // 1. 動的 Spatial Hash を�E構篁E
    w.rebuild_collision();

    // 無敵タイマ�Eを更新
    if w.player.invincible_timer > 0.0 {
        w.player.invincible_timer = (w.player.invincible_timer - dt).max(0.0);
    }

    // 2. プレイヤー周辺の敵を取得して冁E冁E��宁E
    // 最大の敵半征E��Eolem: 32px�E�を老E�Eしてクエリ半征E��庁E��めE
    let max_enemy_radius = 32.0_f32;
    let query_radius = PLAYER_RADIUS + max_enemy_radius;
    w.collision.dynamic.query_nearby_into(px, py, query_radius, &mut w.spatial_query_buf);

    for idx in w.spatial_query_buf.iter().copied() {
        if w.enemies.alive[idx] == 0 { continue; }
        let kind_id = w.enemies.kind_ids[idx];
        let Some(params) = w.params.get_enemy(kind_id) else { continue; };
        let enemy_r = params.radius;
        let hit_radius = PLAYER_RADIUS + enemy_r;
        let ex = w.enemies.positions_x[idx] + enemy_r;
        let ey = w.enemies.positions_y[idx] + enemy_r;
        let ddx = px - ex;
        let ddy = py - ey;
        let dist_sq = ddx * ddx + ddy * ddy;

        if dist_sq < hit_radius * hit_radius {
            // HP の権威�E Elixir 側。ここではイベント発行�Eみ行い、E
            // Elixir ぁEPlayerDamaged を受信して player_hp を減算し、E
            // 次フレームで set_player_hp NIF で注入する、E
            if w.player.invincible_timer <= 0.0 && w.player.hp > 0.0 {
                let dmg = params.damage_per_sec * dt;
                w.player.invincible_timer = INVINCIBLE_DURATION;
                w.frame_events.push(FrameEvent::PlayerDamaged { damage: dmg });
                // 赤ぁE��ーチE��クルを�Eレイヤー位置に発甁E
                let ppx = w.player.x + PLAYER_RADIUS;
                let ppy = w.player.y + PLAYER_RADIUS;
                w.particles.emit(ppx, ppy, 6, [1.0, 0.15, 0.15, 1.0]);
            }
        }
    }

    // ── 武器スロチE��発封E�E琁E──────────────────────────────────────
    update_weapon_attacks(w, dt, px, py);

    // ── パ�EチE��クル更新: 移勁E+ 重力 + フェードアウチE───────────
    update_particles(w, dt);

    // ── アイチE��更新�E�磁石エフェクチE+ 自動収雁E��E────────────────
    update_items(w, dt, px, py);

    // ── 弾丸移勁E+ 弾丸 vs 敵衝突判宁E───────────────────────────
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
