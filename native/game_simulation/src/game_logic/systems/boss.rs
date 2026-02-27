use crate::world::{FrameEvent, GameWorldInner, BULLET_KIND_ROCK};
use crate::constants::{BULLET_RADIUS, INVINCIBLE_DURATION, PLAYER_RADIUS, SCREEN_HEIGHT, SCREEN_WIDTH};
use crate::entity_params::{BossParams, BOSS_ID_BAT_LORD, BOSS_ID_SLIME_KING, BOSS_ID_STONE_GOLEM};
use crate::item::ItemKind;

/// ボス更新（Elixir が spawn_boss で生成したボスを毎フレーム動かす）
pub(crate) fn update_boss(w: &mut GameWorldInner, dt: f32) {
    // 借用競合を避けるため、副作用データを先に収集する
    struct BossEffect {
        spawn_slimes: bool,
        spawn_rocks: bool,
        bat_dash: bool,
        special_x: f32,
        special_y: f32,
        hurt_player: bool,
        hurt_x: f32,
        hurt_y: f32,
        boss_damage: f32,
        bullet_hits: Vec<(usize, f32, bool)>, // (bullet_idx, dmg, kill_bullet)
        boss_x: f32,
        boss_y: f32,
        boss_invincible: bool,
        boss_r: f32,
        boss_exp_reward: u32,
        boss_killed: bool,
        exp_reward: u32,
        kill_x: f32,
        kill_y: f32,
    }
    let mut eff = BossEffect {
        spawn_slimes: false, spawn_rocks: false, bat_dash: false,
        special_x: 0.0, special_y: 0.0,
        hurt_player: false, hurt_x: 0.0, hurt_y: 0.0, boss_damage: 0.0,
        bullet_hits: Vec::new(),
        boss_x: 0.0, boss_y: 0.0, boss_invincible: false,
        boss_r: 0.0, boss_exp_reward: 0,
        boss_killed: false, exp_reward: 0, kill_x: 0.0, kill_y: 0.0,
    };

    // フェーズ1: boss の移動・タイマー更新（boss のみを借用）
    if let Some(boss) = w.boss.as_mut() {
        // プレイヤー座標をコピーして boss 借用前に取得
        let px = w.player.x + PLAYER_RADIUS;
        let py = w.player.y + PLAYER_RADIUS;

        // 無敵タイマー
        if boss.invincible_timer > 0.0 {
            boss.invincible_timer = (boss.invincible_timer - dt).max(0.0);
            if boss.invincible_timer <= 0.0 { boss.invincible = false; }
        }

        // 移動 AI
        let bp = BossParams::get(boss.kind_id);
        match boss.kind_id {
            BOSS_ID_SLIME_KING | BOSS_ID_STONE_GOLEM => {
                let ddx = px - boss.x;
                let ddy = py - boss.y;
                let dist = (ddx * ddx + ddy * ddy).sqrt().max(0.001);
                boss.x += (ddx / dist) * bp.speed * dt;
                boss.y += (ddy / dist) * bp.speed * dt;
            }
            BOSS_ID_BAT_LORD => {
                if boss.is_dashing {
                    boss.x += boss.dash_vx * dt;
                    boss.y += boss.dash_vy * dt;
                    boss.dash_timer -= dt;
                    if boss.dash_timer <= 0.0 {
                        boss.is_dashing = false;
                        boss.invincible = false;
                        boss.invincible_timer = 0.0;
                    }
                } else {
                    let ddx = px - boss.x;
                    let ddy = py - boss.y;
                    let dist = (ddx * ddx + ddy * ddy).sqrt().max(0.001);
                    boss.x += (ddx / dist) * bp.speed * dt;
                    boss.y += (ddy / dist) * bp.speed * dt;
                }
            }
            _ => {}
        }
        boss.x = boss.x.clamp(bp.radius, SCREEN_WIDTH - bp.radius);
        boss.y = boss.y.clamp(bp.radius, SCREEN_HEIGHT - bp.radius);

        // 特殊行動タイマー
        boss.phase_timer -= dt;
        if boss.phase_timer <= 0.0 {
            boss.phase_timer = bp.special_interval;
            match boss.kind_id {
                BOSS_ID_SLIME_KING => {
                    eff.spawn_slimes = true;
                    eff.special_x = boss.x;
                    eff.special_y = boss.y;
                }
                BOSS_ID_BAT_LORD => {
                    let ddx = px - boss.x;
                    let ddy = py - boss.y;
                    let dist = (ddx * ddx + ddy * ddy).sqrt().max(0.001);
                    boss.dash_vx = (ddx / dist) * 500.0;
                    boss.dash_vy = (ddy / dist) * 500.0;
                    boss.is_dashing = true;
                    boss.dash_timer = 0.6;
                    boss.invincible = true;
                    boss.invincible_timer = 0.6;
                    eff.bat_dash = true;
                    eff.special_x = boss.x;
                    eff.special_y = boss.y;
                }
                BOSS_ID_STONE_GOLEM => {
                    eff.spawn_rocks = true;
                    eff.special_x = boss.x;
                    eff.special_y = boss.y;
                }
                _ => {}
            }
        }

        // ボス vs プレイヤー接触ダメージ: フラグだけ立てる
        let boss_r = bp.radius;
        let hit_r = PLAYER_RADIUS + boss_r;
        let ddx = px - boss.x;
        let ddy = py - boss.y;
        if ddx * ddx + ddy * ddy < hit_r * hit_r {
            eff.hurt_player = true;
            eff.hurt_x = px;
            eff.hurt_y = py;
            eff.boss_damage = bp.damage_per_sec;
        }

        // 弾丸 vs ボス: ヒット判定に必要なデータをコピー
        eff.boss_invincible = boss.invincible;
        eff.boss_r = bp.radius;
        eff.boss_exp_reward = bp.exp_reward;
        eff.boss_x = boss.x;
        eff.boss_y = boss.y;
    }

    // 弾丸 vs ボス: boss 借用の外で処理
    if w.boss.is_some() && !eff.boss_invincible {
        let bullet_len = w.bullets.positions_x.len();
        for bi in 0..bullet_len {
            if !w.bullets.alive[bi] { continue; }
            let dmg = w.bullets.damage[bi];
            if dmg == 0 { continue; }
            let bx = w.bullets.positions_x[bi];
            let by = w.bullets.positions_y[bi];
            let hit_r2 = BULLET_RADIUS + eff.boss_r;
            let ddx2 = bx - eff.boss_x;
            let ddy2 = by - eff.boss_y;
            if ddx2 * ddx2 + ddy2 * ddy2 < hit_r2 * hit_r2 {
                eff.bullet_hits.push((bi, dmg as f32, !w.bullets.piercing[bi]));
            }
        }
        // BossDamaged イベントを発行して Elixir 側で HP を減算する。
        // Rust 側の boss.hp は Elixir から set_boss_hp NIF で注入された値を参照する。
        let total_dmg: f32 = eff.bullet_hits.iter().map(|&(_, d, _)| d).sum();
        if total_dmg > 0.0 {
            w.frame_events.push(FrameEvent::BossDamaged { damage: total_dmg });
            // Rust 側でも HP を更新して死亡判定に使用する（Elixir からの注入は次フレーム）
            if let Some(ref mut boss) = w.boss {
                boss.hp -= total_dmg;
                if boss.hp <= 0.0 {
                    eff.boss_killed = true;
                    eff.exp_reward = eff.boss_exp_reward;
                    eff.kill_x = boss.x;
                    eff.kill_y = boss.y;
                }
            }
        }
    }

    // フェーズ2: boss 借用を解放してから副作用を適用
    // HP の権威は Elixir 側。ここではイベント発行のみ行う。
    if eff.hurt_player {
        if w.player.invincible_timer <= 0.0 && w.player.hp > 0.0 {
            let dmg = eff.boss_damage * dt;
            w.player.invincible_timer = INVINCIBLE_DURATION;
            w.frame_events.push(FrameEvent::PlayerDamaged { damage: dmg });
            w.particles.emit(eff.hurt_x, eff.hurt_y, 8, [1.0, 0.15, 0.15, 1.0]);
        }
    }

    // 弾丸ヒットパーティクル & 弾丸消去
    if !eff.bullet_hits.is_empty() {
        w.particles.emit(eff.boss_x, eff.boss_y, 4, [1.0, 0.8, 0.2, 1.0]);
        for &(bi, _, kill_bullet) in &eff.bullet_hits {
            if kill_bullet { w.bullets.kill(bi); }
        }
    }

    // 特殊行動の副作用
    if eff.spawn_slimes {
        let positions: Vec<(f32, f32)> = (0..8)
            .map(|i| {
                let angle = i as f32 * std::f32::consts::TAU / 8.0;
                (eff.special_x + angle.cos() * 120.0, eff.special_y + angle.sin() * 120.0)
            })
            .collect();
        w.enemies.spawn(&positions, 0); // Slime
        w.particles.emit(eff.special_x, eff.special_y, 16, [0.2, 1.0, 0.2, 1.0]);
    }
    if eff.spawn_rocks {
        for (dx_dir, dy_dir) in [(1.0_f32, 0.0_f32), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            w.bullets.spawn_ex(eff.special_x, eff.special_y, dx_dir * 200.0, dy_dir * 200.0, 50, 3.0, false, BULLET_KIND_ROCK, 0);
        }
        w.particles.emit(eff.special_x, eff.special_y, 10, [0.6, 0.6, 0.6, 1.0]);
    }
    if eff.bat_dash {
        w.particles.emit(eff.special_x, eff.special_y, 12, [0.8, 0.2, 1.0, 1.0]);
    }
    if eff.boss_killed {
        let boss_k = w.boss.as_ref().map(|b| b.kind_id).unwrap_or(0);
        // score_popups は描画用なので Rust 側で管理を継続する
        w.score_popups.push((eff.kill_x, eff.kill_y - 20.0, eff.exp_reward * 2, 0.8));
        w.frame_events.push(FrameEvent::BossDefeated { boss_kind: boss_k });
        w.particles.emit(eff.kill_x, eff.kill_y, 40, [1.0, 0.5, 0.0, 1.0]);
        for _ in 0..10 {
            let ox = (w.rng.next_f32() - 0.5) * 200.0;
            let oy = (w.rng.next_f32() - 0.5) * 200.0;
            w.items.spawn(eff.kill_x + ox, eff.kill_y + oy, ItemKind::Gem, eff.exp_reward / 10);
        }
        w.boss = None;
    }
}
