use crate::constants::{BULLET_RADIUS, INVINCIBLE_DURATION, PLAYER_RADIUS};
use crate::world::{FrameEvent, GameWorldInner};

/// Phase 3-B: ボス更新（AI ロジックは Elixir 側に移管済み）
/// Rust はボスの物理的な存在（位置・HP・当たり判定）のみ管理する。
/// - 移動: Elixir が set_boss_velocity NIF で注入した vx/vy で移動する
/// - 特殊行動: Elixir が update_boss_ai コールバックで NIF を呼び出して制御する
/// - 弾丸 vs ボス: Rust が判定し SpecialEntityDamaged/SpecialEntityDefeated イベントを発行する
pub(crate) fn update_boss(w: &mut GameWorldInner, dt: f32) {
    struct BossEffect {
        hurt_player: bool,
        hurt_x: f32,
        hurt_y: f32,
        boss_damage: f32,
        bullet_hits: Vec<(usize, f32, bool)>,
        boss_x: f32,
        boss_y: f32,
        boss_invincible: bool,
        boss_r: f32,
        boss_killed: bool,
        kill_x: f32,
        kill_y: f32,
    }
    let mut eff = BossEffect {
        hurt_player: false,
        hurt_x: 0.0,
        hurt_y: 0.0,
        boss_damage: 0.0,
        bullet_hits: Vec::new(),
        boss_x: 0.0,
        boss_y: 0.0,
        boss_invincible: false,
        boss_r: 0.0,
        boss_killed: false,
        kill_x: 0.0,
        kill_y: 0.0,
    };

    if w.boss.is_some() {
        let px = w.player.x + PLAYER_RADIUS;
        let py = w.player.y + PLAYER_RADIUS;
        let map_w = w.map_width;
        let map_h = w.map_height;

        let Some(boss) = w.boss.as_mut() else {
            return;
        };
        let boss_r = boss.radius;

        // Elixir から注入された速度ベクトルで移動する
        boss.x += boss.vx * dt;
        boss.y += boss.vy * dt;
        boss.x = boss.x.clamp(boss_r, map_w - boss_r);
        boss.y = boss.y.clamp(boss_r, map_h - boss_r);

        // ボス vs プレイヤー接触ダメージ
        // damage_per_sec は Elixir 側が管理するため、ここでは固定値を使用する
        // （将来的に set_boss_damage_per_sec NIF で注入可能）
        let hit_r = PLAYER_RADIUS + boss_r;
        let ddx = px - boss.x;
        let ddy = py - boss.y;
        if ddx * ddx + ddy * ddy < hit_r * hit_r {
            eff.hurt_player = true;
            eff.hurt_x = px;
            eff.hurt_y = py;
            eff.boss_damage = boss.damage_per_sec;
        }

        eff.boss_invincible = boss.invincible;
        eff.boss_r = boss_r;
        eff.boss_x = boss.x;
        eff.boss_y = boss.y;
    }

    // 弾丸 vs ボス
    if w.boss.is_some() && !eff.boss_invincible {
        let bullet_len = w.bullets.positions_x.len();
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
            let hit_r2 = BULLET_RADIUS + eff.boss_r;
            let ddx2 = bx - eff.boss_x;
            let ddy2 = by - eff.boss_y;
            if ddx2 * ddx2 + ddy2 * ddy2 < hit_r2 * hit_r2 {
                eff.bullet_hits
                    .push((bi, dmg as f32, !w.bullets.piercing[bi]));
            }
        }
        let total_dmg: f32 = eff.bullet_hits.iter().map(|&(_, d, _)| d).sum();
        if total_dmg > 0.0 {
            w.frame_events
                .push(FrameEvent::SpecialEntityDamaged { damage: total_dmg });
            if let Some(ref mut boss) = w.boss {
                boss.hp -= total_dmg;
                if boss.hp <= 0.0 {
                    eff.boss_killed = true;
                    eff.kill_x = boss.x;
                    eff.kill_y = boss.y;
                }
            }
        }
    }

    if eff.hurt_player {
        if w.player.invincible_timer <= 0.0 && w.player.hp > 0.0 {
            let dmg = eff.boss_damage * dt;
            w.player.invincible_timer = INVINCIBLE_DURATION;
            w.frame_events
                .push(FrameEvent::PlayerDamaged { damage: dmg });
            w.particles
                .emit(eff.hurt_x, eff.hurt_y, 8, [1.0, 0.15, 0.15, 1.0]);
        }
    }

    if !eff.bullet_hits.is_empty() {
        w.particles
            .emit(eff.boss_x, eff.boss_y, 4, [1.0, 0.8, 0.2, 1.0]);
        for &(bi, _, kill_bullet) in &eff.bullet_hits {
            if kill_bullet {
                w.bullets.kill(bi);
            }
        }
    }

    if eff.boss_killed {
        w.frame_events.push(FrameEvent::SpecialEntityDefeated {
            x: eff.kill_x,
            y: eff.kill_y,
        });
        w.particles
            .emit(eff.kill_x, eff.kill_y, 40, [1.0, 0.5, 0.0, 1.0]);
        w.boss = None;
    }
}
