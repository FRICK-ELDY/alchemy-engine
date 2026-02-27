use crate::world::{FrameEvent, GameWorldInner};
use game_core::constants::{BULLET_RADIUS, MAP_HEIGHT, MAP_WIDTH};
use game_core::entity_params::EnemyParams;
use game_core::item::ItemKind;

pub(crate) fn update_projectiles_and_enemy_hits(w: &mut GameWorldInner, dt: f32) {
    // 弾丸を移動・寿命更新
    let bullet_len = w.bullets.len();
    for i in 0..bullet_len {
        if !w.bullets.alive[i] {
            continue;
        }
        w.bullets.positions_x[i] += w.bullets.velocities_x[i] * dt;
        w.bullets.positions_y[i] += w.bullets.velocities_y[i] * dt;
        w.bullets.lifetime[i] -= dt;
        if w.bullets.lifetime[i] <= 0.0 {
            w.bullets.kill(i);
            continue;
        }
        // 1.5.2: 障害物に当たったら弾を消す
        let bx = w.bullets.positions_x[i];
        let by = w.bullets.positions_y[i];
        w.collision
            .query_static_nearby_into(bx, by, BULLET_RADIUS, &mut w.obstacle_query_buf);
        if !w.obstacle_query_buf.is_empty() {
            w.bullets.kill(i);
            continue;
        }
        // 画面外に出た弾丸も消す
        if bx < -100.0 || bx > MAP_WIDTH + 100.0 || by < -100.0 || by > MAP_HEIGHT + 100.0 {
            w.bullets.kill(i);
        }
    }

    // 弾丸 vs 敵 衝突判定
    let bullet_query_r = BULLET_RADIUS + 32.0_f32;
    for bi in 0..bullet_len {
        if !w.bullets.alive[bi] {
            continue;
        }
        let dmg = w.bullets.damage[bi];
        // ダメージ 0 はエフェクト専用弾（Whip / Lightning）— 衝突判定をスキップ
        if dmg == 0 {
            continue;
        }
        let bx = w.bullets.positions_x[bi];
        let by = w.bullets.positions_y[bi];
        let piercing = w.bullets.piercing[bi];

        let nearby = w.collision.dynamic.query_nearby(bx, by, bullet_query_r);
        for ei in nearby {
            if !w.enemies.alive[ei] {
                continue;
            }
            let kind_id = w.enemies.kind_ids[ei];
            let ep = EnemyParams::get(kind_id);
            let enemy_r = ep.radius;
            let hit_r = BULLET_RADIUS + enemy_r;
            let ex = w.enemies.positions_x[ei] + enemy_r;
            let ey = w.enemies.positions_y[ei] + enemy_r;
            let ddx = bx - ex;
            let ddy = by - ey;
            if ddx * ddx + ddy * ddy < hit_r * hit_r {
                w.enemies.hp[ei] -= dmg as f32;
                if w.enemies.hp[ei] <= 0.0 {
                    let weapon_k = w.bullets.weapon_kind[bi];
                    w.enemies.kill(ei);
                    // フェーズ1: score/kill_count の権威は Elixir 側に移行。
                    // フェーズ3: exp/level/level_up_pending の権威は Elixir 側に移行。
                    // score_popups は描画用なので Rust 側で管理を継続する。
                    w.score_popups.push((ex, ey - 20.0, ep.exp_reward * 2, 0.8));
                    w.frame_events.push(FrameEvent::EnemyKilled {
                        enemy_kind: kind_id,
                        weapon_kind: weapon_k,
                    });
                    w.particles.emit(ex, ey, 8, ep.particle_color);
                    let roll = w.rng.next_u32() % 100;
                    let (item_kind, item_value) = if roll < 2 {
                        (ItemKind::Magnet, 0)
                    } else if roll < 7 {
                        (ItemKind::Potion, 20)
                    } else {
                        (ItemKind::Gem, ep.exp_reward)
                    };
                    w.items.spawn(ex, ey, item_kind, item_value);
                } else {
                    let hit_color = if piercing {
                        [1.0, 0.4, 0.0, 1.0]
                    } else {
                        [1.0, 0.9, 0.3, 1.0]
                    };
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
