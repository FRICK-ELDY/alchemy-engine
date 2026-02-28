use crate::world::{FrameEvent, GameWorldInner};
use crate::constants::BULLET_RADIUS;
use crate::entity_params::{DEFAULT_ENEMY_RADIUS, DEFAULT_PARTICLE_COLOR};

pub(crate) fn update_projectiles_and_enemy_hits(w: &mut GameWorldInner, dt: f32) {
    // ── 弾丸を移動・寿命更新 ─────────────────────────────────────
    let bullet_len = w.bullets.len();
    for i in 0..bullet_len {
        if !w.bullets.alive[i] { continue; }
        w.bullets.positions_x[i] += w.bullets.velocities_x[i] * dt;
        w.bullets.positions_y[i] += w.bullets.velocities_y[i] * dt;
        w.bullets.lifetime[i] -= dt;
        if w.bullets.lifetime[i] <= 0.0 {
            w.bullets.kill(i);
            continue;
        }
        // 障害物に当たったら弾を消す
        let bx = w.bullets.positions_x[i];
        let by = w.bullets.positions_y[i];
        w.collision.query_static_nearby_into(bx, by, BULLET_RADIUS, &mut w.obstacle_query_buf);
        if !w.obstacle_query_buf.is_empty() {
            w.bullets.kill(i);
            continue;
        }
        // マップ外に出た弾丸も消す（map_width / map_height は GameWorldInner から参照）
        if bx < -100.0 || bx > w.map_width + 100.0 || by < -100.0 || by > w.map_height + 100.0 {
            w.bullets.kill(i);
        }
    }

    // ── 弾丸 vs 敵 衝突判定 ──────────────────────────────────────
    let bullet_query_r = BULLET_RADIUS + 32.0_f32;
    for bi in 0..bullet_len {
        if !w.bullets.alive[bi] { continue; }
        let dmg = w.bullets.damage[bi];
        // ダメージ 0 はエフェクト専用弾（Whip / Lightning）— 衝突判定をスキップ
        if dmg == 0 { continue; }
        let bx = w.bullets.positions_x[bi];
        let by = w.bullets.positions_y[bi];
        let piercing = w.bullets.piercing[bi];

        w.collision.dynamic.query_nearby_into(bx, by, bullet_query_r, &mut w.spatial_query_buf);
        for ei in w.spatial_query_buf.iter().copied() {
            if !w.enemies.alive[ei] { continue; }
            let kind_id = w.enemies.kind_ids[ei];
            let (enemy_r, particle_color) = w.params.get_enemy(kind_id)
                .map(|e| (e.radius, e.particle_color))
                .unwrap_or((DEFAULT_ENEMY_RADIUS, DEFAULT_PARTICLE_COLOR));
            let hit_r = BULLET_RADIUS + enemy_r;
            let ex = w.enemies.positions_x[ei] + enemy_r;
            let ey = w.enemies.positions_y[ei] + enemy_r;
            let ddx = bx - ex;
            let ddy = by - ey;
            if ddx * ddx + ddy * ddy < hit_r * hit_r {
                w.enemies.hp[ei] -= dmg as f32;
                if w.enemies.hp[ei] <= 0.0 {
                    w.enemies.kill(ei);
                    w.frame_events.push(FrameEvent::EnemyKilled { enemy_kind: kind_id, x: ex, y: ey });
                    w.particles.emit(ex, ey, 8, particle_color);
                } else {
                    let hit_color = if piercing { [1.0, 0.4, 0.0, 1.0] } else { [1.0, 0.9, 0.3, 1.0] };
                    w.particles.emit(ex, ey, 3, hit_color);
                }
                // 貫通弾は消えない、通常弾は消す
                if !piercing {
                    w.bullets.kill(bi);
                    break;
                }
            }
        }
    }
}
