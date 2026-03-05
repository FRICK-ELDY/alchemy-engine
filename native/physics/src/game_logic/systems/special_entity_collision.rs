//! Path: native/physics/src/game_logic/systems/special_entity_collision.rs
//! Summary: 特殊エンティティ（ボス）の衝突判定
//!
//! Elixir SSoT 移行後: Rust は永続状態を持たず、スナップショットで衝突のみ判定。
//! SpecialEntityDamaged / PlayerDamaged を発行。SpecialEntityDefeated は発行しない。

use crate::constants::{BULLET_RADIUS, PLAYER_RADIUS};
use crate::world::{FrameEvent, GameWorldInner};

/// 特殊エンティティスナップショットと弾丸・プレイヤーとの衝突を判定する。
/// HP 減算・撃破判定は Elixir が行う。
pub(crate) fn collide_special_entity_snapshot(w: &mut GameWorldInner, dt: f32) {
    let Some(ref snap) = w.special_entity_snapshot else {
        return;
    };

    let px = w.player.x + PLAYER_RADIUS;
    let py = w.player.y + PLAYER_RADIUS;
    let hit_r = PLAYER_RADIUS + snap.radius;
    let ddx = px - snap.x;
    let ddy = py - snap.y;

    // ボス vs プレイヤー接触ダメージ（HP・無敵は contents SSoT）
    if ddx * ddx + ddy * ddy < hit_r * hit_r
        && !snap.invincible
        && w.player_invincible_timer_injected <= 0.0
        && w.player_hp_injected > 0.0
    {
        let dmg = snap.damage_per_sec * dt;
        w.frame_events
            .push(FrameEvent::PlayerDamaged { damage: dmg });
        w.particles.emit(px, py, 8, [1.0, 0.15, 0.15, 1.0]);
    }

    // 弾丸 vs ボス
    if !snap.invincible {
        let bullet_len = w.bullets.positions_x.len();
        let mut bullet_hits: Vec<(usize, f32, bool)> = Vec::new();

        for bi in 0..bullet_len {
            if !w.bullets.alive[bi] {
                continue;
            }
            let dmg = w.bullets.damage[bi];
            if dmg == 0 {
                continue;
            }
            let bx = w.bullets.positions_x[bi];
            let by = w.bullets.positions_y[bi];
            let hit_r2 = BULLET_RADIUS + snap.radius;
            let ddx2 = bx - snap.x;
            let ddy2 = by - snap.y;
            if ddx2 * ddx2 + ddy2 * ddy2 < hit_r2 * hit_r2 {
                bullet_hits.push((bi, dmg as f32, !w.bullets.piercing[bi]));
            }
        }

        let total_dmg: f32 = bullet_hits.iter().map(|&(_, d, _)| d).sum();
        if total_dmg > 0.0 {
            w.frame_events
                .push(FrameEvent::SpecialEntityDamaged { damage: total_dmg });
            w.particles
                .emit(snap.x, snap.y, 4, [1.0, 0.8, 0.2, 1.0]);
            for (bi, _, kill_bullet) in bullet_hits {
                if kill_bullet {
                    w.bullets.kill(bi);
                }
            }
        }
    }
}
