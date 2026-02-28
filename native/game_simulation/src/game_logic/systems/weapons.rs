use crate::game_logic::{find_nearest_enemy_spatial, find_nearest_enemy_spatial_excluding};
use crate::world::{FrameEvent, GameWorldInner, BULLET_KIND_LIGHTNING, BULLET_KIND_WHIP};
use crate::constants::{BULLET_LIFETIME, BULLET_SPEED, WEAPON_SEARCH_RADIUS};
use crate::entity_params::{
    garlic_radius, lightning_chain_count, whip_range, EnemyParams, WeaponParams, WEAPON_ID_AXE,
    WEAPON_ID_CROSS, WEAPON_ID_FIREBALL, WEAPON_ID_GARLIC, WEAPON_ID_LIGHTNING,
    WEAPON_ID_MAGIC_WAND, WEAPON_ID_WHIP,
};
use crate::item::ItemKind;

pub(crate) fn update_weapon_attacks(w: &mut GameWorldInner, dt: f32, px: f32, py: f32) {
    // プレイヤーの移動方向（Whip の向き計算用）
    let facing_angle = {
        let fdx = w.player.input_dx;
        let fdy = w.player.input_dy;
        if fdx * fdx + fdy * fdy > 0.0001 {
            fdy.atan2(fdx)
        } else {
            // 停止中は右向きをデフォルトとする
            0.0_f32
        }
    };

    let slot_count = w.weapon_slots.len();
    for si in 0..slot_count {
        w.weapon_slots[si].cooldown_timer = (w.weapon_slots[si].cooldown_timer - dt).max(0.0);
        if w.weapon_slots[si].cooldown_timer > 0.0 {
            continue;
        }

        let kind_id = w.weapon_slots[si].kind_id;
        let wp = WeaponParams::get(kind_id);
        // レベルに応じたクールダウン・ダメージ・弾数を使用
        let cd = w.weapon_slots[si].effective_cooldown();
        let dmg = w.weapon_slots[si].effective_damage();
        let level = w.weapon_slots[si].level;
        let bcount = w.weapon_slots[si].bullet_count();

        match kind_id {
            WEAPON_ID_MAGIC_WAND => fire_magic_wand(w, si, px, py, dmg, bcount, wp.as_u8, cd),
            WEAPON_ID_AXE => fire_axe(w, si, px, py, dmg, wp.as_u8, cd),
            WEAPON_ID_CROSS => fire_cross(w, si, px, py, dmg, bcount, wp.as_u8, cd),
            WEAPON_ID_WHIP => fire_whip(w, si, px, py, dmg, level, kind_id, wp.as_u8, cd, facing_angle),
            WEAPON_ID_FIREBALL => fire_fireball(w, si, px, py, dmg, wp.as_u8, cd),
            WEAPON_ID_LIGHTNING => {
                fire_lightning(w, si, px, py, dmg, level, kind_id, wp.as_u8, cd)
            }
            WEAPON_ID_GARLIC => fire_garlic(w, si, px, py, dmg, level, kind_id, wp.as_u8, cd),
            _ => {}
        }
    }
}

fn fire_magic_wand(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    bcount: usize,
    weapon_kind: u8,
    cd: f32,
) {
    let mut buf: Vec<usize> = Vec::new();
    if let Some(ti) = find_nearest_enemy_spatial(&w.collision, &w.enemies, px, py, WEAPON_SEARCH_RADIUS, &mut buf) {
        let target_r = EnemyParams::get(w.enemies.kind_ids[ti]).radius;
        let tx = w.enemies.positions_x[ti] + target_r;
        let ty = w.enemies.positions_y[ti] + target_r;
        let bdx = tx - px;
        let bdy = ty - py;
        // bcount 発同時発射（Lv3 で 2 発、Lv5 で 3 発）
        // 複数発は少しずつ角度をずらして扇状に発射
        let base_angle = bdy.atan2(bdx);
        let spread = std::f32::consts::PI * 0.08; // 約 14 度の広がり
        let half = (bcount as f32 - 1.0) / 2.0;
        for bi in 0..bcount {
            let angle = base_angle + (bi as f32 - half) * spread;
            let vx = angle.cos() * BULLET_SPEED;
            let vy = angle.sin() * BULLET_SPEED;
            w.bullets.spawn(px, py, vx, vy, dmg, BULLET_LIFETIME, weapon_kind);
        }
        w.weapon_slots[si].cooldown_timer = cd;
    }
}

fn fire_axe(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    weapon_kind: u8,
    cd: f32,
) {
    // 上方向に直進（簡易実装）
    w.bullets.spawn(px, py, 0.0, -BULLET_SPEED, dmg, BULLET_LIFETIME, weapon_kind);
    w.weapon_slots[si].cooldown_timer = cd;
}

fn fire_cross(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    bcount: usize,
    weapon_kind: u8,
    cd: f32,
) {
    // Lv1〜3: 上下左右 4 方向、Lv4 以上: 斜め 4 方向も追加
    let dirs_4: [(f32, f32); 4] = [(0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)];
    let diag = std::f32::consts::FRAC_1_SQRT_2;
    let dirs_8: [(f32, f32); 8] = [
        (0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0),
        (diag, -diag), (-diag, -diag), (diag, diag), (-diag, diag),
    ];
    let dirs: &[(f32, f32)] = if bcount >= 8 { &dirs_8 } else { &dirs_4 };
    for &(dx_dir, dy_dir) in dirs {
        w.bullets.spawn(px, py, dx_dir * BULLET_SPEED, dy_dir * BULLET_SPEED, dmg, BULLET_LIFETIME, weapon_kind);
    }
    w.weapon_slots[si].cooldown_timer = cd;
}

fn fire_whip(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    level: u32,
    kind_id: u8,
    weapon_kind: u8,
    cd: f32,
    facing_angle: f32,
) {
    // プレイヤーの移動方向に扇状の判定を出す（弾丸を生成しない直接判定）
    let range = whip_range(kind_id, level);
    let whip_half_angle = std::f32::consts::PI * 0.3; // 108度 / 2 = 54度
    // facing_angle 方向の中間点にエフェクト弾を生成（黄緑の横長楕円）
    let eff_x = px + facing_angle.cos() * range * 0.5;
    let eff_y = py + facing_angle.sin() * range * 0.5;
    w.bullets.spawn_effect(eff_x, eff_y, 0.12, BULLET_KIND_WHIP);
    // 空間ハッシュで範囲内の候補のみ取得し、全敵ループを回避
    let whip_range_sq = range * range;
    let mut whip_buf: Vec<usize> = Vec::new();
    w.collision.dynamic.query_nearby_into(px, py, range, &mut whip_buf);
    for ei in whip_buf {
        if !w.enemies.alive[ei] {
            continue;
        }
        let ex = w.enemies.positions_x[ei];
        let ey = w.enemies.positions_y[ei];
        let ddx = ex - px;
        let ddy = ey - py;
        // sqrt を避けて二乗比較で正確な円形クリップ
        if ddx * ddx + ddy * ddy > whip_range_sq {
            continue;
        }
        let angle = ddy.atan2(ddx);
        // π/-π をまたぐ場合に正しく動作するよう -π〜π に正規化
        let diff = (angle - facing_angle + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU) - std::f32::consts::PI;
        if diff.abs() < whip_half_angle {
            let enemy_r = EnemyParams::get(w.enemies.kind_ids[ei]).radius;
            let hit_x = ex + enemy_r;
            let hit_y = ey + enemy_r;
            w.enemies.hp[ei] -= dmg as f32;
            if w.enemies.hp[ei] <= 0.0 {
                let kind_e = w.enemies.kind_ids[ei];
                let ep_hit = EnemyParams::get(kind_e);
                w.enemies.kill(ei);
                // score_popups は描画用なので Rust 側で管理を継続する
                w.score_popups.push((hit_x, hit_y - 20.0, ep_hit.exp_reward * 2, 0.8));
                w.frame_events.push(FrameEvent::EnemyKilled { enemy_kind: kind_e, weapon_kind });
                w.particles.emit(hit_x, hit_y, 8, ep_hit.particle_color);
                let roll = w.rng.next_u32() % 100;
                let (item_kind, item_value) = if roll < 2 {
                    (ItemKind::Magnet, 0)
                } else if roll < 7 {
                    (ItemKind::Potion, 20)
                } else {
                    (ItemKind::Gem, ep_hit.exp_reward)
                };
                w.items.spawn(hit_x, hit_y, item_kind, item_value);
            } else {
                w.particles.emit(hit_x, hit_y, 3, [1.0, 0.6, 0.1, 1.0]);
            }
        }
    }
    // Whip vs ボス
    {
        let boss_hit_pos: Option<(f32, f32)> = if let Some(ref boss) = w.boss {
            if !boss.invincible {
                let ddx = boss.x - px;
                let ddy = boss.y - py;
                if ddx * ddx + ddy * ddy <= whip_range_sq {
                    let angle = ddy.atan2(ddx);
                    let diff = (angle - facing_angle + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU) - std::f32::consts::PI;
                    if diff.abs() < whip_half_angle { Some((boss.x, boss.y)) } else { None }
                } else { None }
            } else { None }
        } else { None };
        if let Some((bx, by)) = boss_hit_pos {
            if let Some(ref mut boss) = w.boss { boss.hp -= dmg as f32; }
            w.particles.emit(bx, by, 4, [1.0, 0.8, 0.2, 1.0]);
        }
    }
    w.weapon_slots[si].cooldown_timer = cd;
}

fn fire_fireball(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    weapon_kind: u8,
    cd: f32,
) {
    let mut buf: Vec<usize> = Vec::new();
    // 最近接敵に向かって貫通弾を発射
    if let Some(ti) = find_nearest_enemy_spatial(&w.collision, &w.enemies, px, py, WEAPON_SEARCH_RADIUS, &mut buf) {
        let target_r = EnemyParams::get(w.enemies.kind_ids[ti]).radius;
        let tx = w.enemies.positions_x[ti] + target_r;
        let ty = w.enemies.positions_y[ti] + target_r;
        let bdx = tx - px;
        let bdy = ty - py;
        let base_angle = bdy.atan2(bdx);
        let vx = base_angle.cos() * BULLET_SPEED;
        let vy = base_angle.sin() * BULLET_SPEED;
        w.bullets.spawn_piercing(px, py, vx, vy, dmg, BULLET_LIFETIME, weapon_kind);
        w.weapon_slots[si].cooldown_timer = cd;
    }
}

fn fire_lightning(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    level: u32,
    kind_id: u8,
    weapon_kind: u8,
    cd: f32,
) {
    // 最近接敵から始まり、最大 chain_count 体に連鎖
    let chain_count = lightning_chain_count(kind_id, level);
    // chain_count は最大 6 程度と小さいため Vec で十分（HashSet 不要）
    let mut hit_vec: Vec<usize> = Vec::with_capacity(chain_count);
    // 最初はプレイヤー位置から最近接敵を探す（空間ハッシュで候補を絞る）
    let mut spatial_buf: Vec<usize> = Vec::new();
    let mut current = find_nearest_enemy_spatial(&w.collision, &w.enemies, px, py, WEAPON_SEARCH_RADIUS, &mut spatial_buf);
    #[allow(unused_assignments)]
    let mut next_search_x = px;
    #[allow(unused_assignments)]
    let mut next_search_y = py;
    for _ in 0..chain_count {
        if let Some(ei) = current {
            let enemy_r = EnemyParams::get(w.enemies.kind_ids[ei]).radius;
            let hit_x = w.enemies.positions_x[ei] + enemy_r;
            let hit_y = w.enemies.positions_y[ei] + enemy_r;
            w.enemies.hp[ei] -= dmg as f32;
            // 電撃エフェクト弾（水色の電撃球）+ パーティクル
            w.bullets.spawn_effect(hit_x, hit_y, 0.10, BULLET_KIND_LIGHTNING);
            w.particles.emit(hit_x, hit_y, 5, [0.3, 0.8, 1.0, 1.0]);
            if w.enemies.hp[ei] <= 0.0 {
                let kind_e = w.enemies.kind_ids[ei];
                let ep_chain = EnemyParams::get(kind_e);
                w.enemies.kill(ei);
                // score_popups は描画用なので Rust 側で管理を継続する
                w.score_popups.push((hit_x, hit_y - 20.0, ep_chain.exp_reward * 2, 0.8));
                w.frame_events.push(FrameEvent::EnemyKilled { enemy_kind: kind_e, weapon_kind });
                let roll = w.rng.next_u32() % 100;
                let (item_kind, item_value) = if roll < 2 {
                    (ItemKind::Magnet, 0)
                } else if roll < 7 {
                    (ItemKind::Potion, 20)
                } else {
                    (ItemKind::Gem, ep_chain.exp_reward)
                };
                w.items.spawn(hit_x, hit_y, item_kind, item_value);
            }
            hit_vec.push(ei);
            next_search_x = hit_x;
            next_search_y = hit_y;
            current = find_nearest_enemy_spatial_excluding(
                &w.collision, &w.enemies, next_search_x, next_search_y,
                WEAPON_SEARCH_RADIUS, &hit_vec, &mut spatial_buf,
            );
        } else {
            break;
        }
    }
    // Lightning vs ボス（600px 以内なら連鎖先としてダメージ）
    {
        let boss_hit_pos: Option<(f32, f32)> = if let Some(ref boss) = w.boss {
            if !boss.invincible {
                let ddx = boss.x - px;
                let ddy = boss.y - py;
                if ddx * ddx + ddy * ddy < 600.0 * 600.0 { Some((boss.x, boss.y)) } else { None }
            } else { None }
        } else { None };
        if let Some((bx, by)) = boss_hit_pos {
            if let Some(ref mut boss) = w.boss { boss.hp -= dmg as f32; }
            w.bullets.spawn_effect(bx, by, 0.10, BULLET_KIND_LIGHTNING);
            w.particles.emit(bx, by, 5, [0.3, 0.8, 1.0, 1.0]);
        }
    }
    w.weapon_slots[si].cooldown_timer = cd;
}

fn fire_garlic(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    level: u32,
    kind_id: u8,
    weapon_kind: u8,
    cd: f32,
) {
    // プレイヤー周囲オーラで一定間隔ダメージ（5 dmg/sec 想定: 0.2s 毎に 1）
    let radius = garlic_radius(kind_id, level);
    let radius_sq = radius * radius;
    let mut garlic_buf: Vec<usize> = Vec::new();
    w.collision.dynamic.query_nearby_into(px, py, radius, &mut garlic_buf);
    for ei in garlic_buf {
        if !w.enemies.alive[ei] { continue; }
        let ex = w.enemies.positions_x[ei];
        let ey = w.enemies.positions_y[ei];
        let ddx = ex - px;
        let ddy = ey - py;
        if ddx * ddx + ddy * ddy > radius_sq { continue; }
        w.enemies.hp[ei] -= dmg as f32;
        let kind_e = w.enemies.kind_ids[ei];
        let ep = EnemyParams::get(kind_e);
        let hit_x = ex + ep.radius;
        let hit_y = ey + ep.radius;
        if w.enemies.hp[ei] <= 0.0 {
            w.enemies.kill(ei);
            // score_popups は描画用なので Rust 側で管理を継続する
            w.score_popups.push((hit_x, hit_y - 20.0, ep.exp_reward * 2, 0.8));
            w.frame_events.push(FrameEvent::EnemyKilled { enemy_kind: kind_e, weapon_kind });
            w.particles.emit(hit_x, hit_y, 8, ep.particle_color);
            let roll = w.rng.next_u32() % 100;
            let (item_kind, item_value) = if roll < 2 {
                (ItemKind::Magnet, 0)
            } else if roll < 7 {
                (ItemKind::Potion, 20)
            } else {
                (ItemKind::Gem, ep.exp_reward)
            };
            w.items.spawn(hit_x, hit_y, item_kind, item_value);
        } else {
            w.particles.emit(hit_x, hit_y, 2, [0.9, 0.9, 0.3, 0.6]);
        }
    }
    w.weapon_slots[si].cooldown_timer = cd;
}
