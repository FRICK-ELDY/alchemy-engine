use crate::game_logic::{find_nearest_enemy_spatial, find_nearest_enemy_spatial_excluding};
use crate::world::{FrameEvent, GameWorldInner, BULLET_KIND_LIGHTNING, BULLET_KIND_WHIP};
use crate::constants::{BULLET_LIFETIME, BULLET_SPEED, WEAPON_SEARCH_RADIUS};
use crate::entity_params::FirePattern;

pub(crate) fn update_weapon_attacks(w: &mut GameWorldInner, dt: f32, px: f32, py: f32) {
    if w.params.weapons.is_empty() {
        return;
    }

    let facing_angle = {
        let fdx = w.player.input_dx;
        let fdy = w.player.input_dy;
        if fdx * fdx + fdy * fdy > 0.0001 {
            fdy.atan2(fdx)
        } else {
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
        let wp = w.params.get_weapon(kind_id);
        let cd     = w.weapon_slots[si].effective_cooldown(wp);
        let dmg    = w.weapon_slots[si].effective_damage(wp);
        let level  = w.weapon_slots[si].level;
        let bcount = w.weapon_slots[si].bullet_count(wp);
        let pattern = wp.fire_pattern.clone();

        match pattern {
            FirePattern::Aimed   => fire_aimed(w, si, px, py, dmg, bcount, cd),
            FirePattern::FixedUp => fire_fixed_up(w, si, px, py, dmg, cd),
            FirePattern::Radial  => fire_radial(w, si, px, py, dmg, bcount, cd),
            FirePattern::Whip    => fire_whip(w, si, px, py, dmg, level, kind_id, cd, facing_angle),
            FirePattern::Piercing => fire_piercing(w, si, px, py, dmg, cd),
            FirePattern::Chain   => fire_chain(w, si, px, py, dmg, level, kind_id, cd),
            FirePattern::Aura    => fire_aura(w, si, px, py, dmg, level, kind_id, cd),
        }
    }
}

fn fire_aimed(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    bcount: usize,
    cd: f32,
) {
    if let Some(ti) = find_nearest_enemy_spatial(&w.collision, &w.enemies, px, py, WEAPON_SEARCH_RADIUS, &mut w.spatial_query_buf) {
        let target_r = w.params.get_enemy(w.enemies.kind_ids[ti]).radius;
        let tx = w.enemies.positions_x[ti] + target_r;
        let ty = w.enemies.positions_y[ti] + target_r;
        let base_angle = (ty - py).atan2(tx - px);
        let spread = std::f32::consts::PI * 0.08;
        let half = (bcount as f32 - 1.0) / 2.0;
        for bi in 0..bcount {
            let angle = base_angle + (bi as f32 - half) * spread;
            let vx = angle.cos() * BULLET_SPEED;
            let vy = angle.sin() * BULLET_SPEED;
            w.bullets.spawn(px, py, vx, vy, dmg, BULLET_LIFETIME);
        }
        w.weapon_slots[si].cooldown_timer = cd;
    }
}

fn fire_fixed_up(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    cd: f32,
) {
    w.bullets.spawn(px, py, 0.0, -BULLET_SPEED, dmg, BULLET_LIFETIME);
    w.weapon_slots[si].cooldown_timer = cd;
}

fn fire_radial(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    bcount: usize,
    cd: f32,
) {
    let dirs_4: [(f32, f32); 4] = [(0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)];
    let diag = std::f32::consts::FRAC_1_SQRT_2;
    let dirs_8: [(f32, f32); 8] = [
        (0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0),
        (diag, -diag), (-diag, -diag), (diag, diag), (-diag, diag),
    ];
    let dirs: &[(f32, f32)] = if bcount >= 8 { &dirs_8 } else { &dirs_4 };
    for &(dx_dir, dy_dir) in dirs {
        w.bullets.spawn(px, py, dx_dir * BULLET_SPEED, dy_dir * BULLET_SPEED, dmg, BULLET_LIFETIME);
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
    cd: f32,
    facing_angle: f32,
) {
    let range = w.params.get_weapon(kind_id).whip_range(level);
    let whip_half_angle = std::f32::consts::PI * 0.3;
    let eff_x = px + facing_angle.cos() * range * 0.5;
    let eff_y = py + facing_angle.sin() * range * 0.5;
    w.bullets.spawn_effect(eff_x, eff_y, 0.12, BULLET_KIND_WHIP);
    let whip_range_sq = range * range;
    w.collision.dynamic.query_nearby_into(px, py, range, &mut w.spatial_query_buf);
    for ei in w.spatial_query_buf.iter().copied() {
        if !w.enemies.alive[ei] {
            continue;
        }
        let ex = w.enemies.positions_x[ei];
        let ey = w.enemies.positions_y[ei];
        let ddx = ex - px;
        let ddy = ey - py;
        if ddx * ddx + ddy * ddy > whip_range_sq {
            continue;
        }
        let angle = ddy.atan2(ddx);
        let diff = (angle - facing_angle + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU) - std::f32::consts::PI;
        if diff.abs() < whip_half_angle {
            let enemy_r = w.params.get_enemy(w.enemies.kind_ids[ei]).radius;
            let hit_x = ex + enemy_r;
            let hit_y = ey + enemy_r;
            w.enemies.hp[ei] -= dmg as f32;
            if w.enemies.hp[ei] <= 0.0 {
                let kind_e = w.enemies.kind_ids[ei];
                let ep_hit = w.params.get_enemy(kind_e).clone();
                w.enemies.kill(ei);
                w.frame_events.push(FrameEvent::EnemyKilled { enemy_kind: kind_e, x: hit_x, y: hit_y });
                w.particles.emit(hit_x, hit_y, 8, ep_hit.particle_color);
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

fn fire_piercing(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    cd: f32,
) {
    if let Some(ti) = find_nearest_enemy_spatial(&w.collision, &w.enemies, px, py, WEAPON_SEARCH_RADIUS, &mut w.spatial_query_buf) {
        let target_r = w.params.get_enemy(w.enemies.kind_ids[ti]).radius;
        let tx = w.enemies.positions_x[ti] + target_r;
        let ty = w.enemies.positions_y[ti] + target_r;
        let base_angle = (ty - py).atan2(tx - px);
        let vx = base_angle.cos() * BULLET_SPEED;
        let vy = base_angle.sin() * BULLET_SPEED;
        w.bullets.spawn_piercing(px, py, vx, vy, dmg, BULLET_LIFETIME);
        w.weapon_slots[si].cooldown_timer = cd;
    }
}

fn fire_chain(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    level: u32,
    kind_id: u8,
    cd: f32,
) {
    let chain_count = w.params.get_weapon(kind_id).chain_count_for_level(level);
    let mut hit_vec: Vec<usize> = Vec::with_capacity(chain_count);
    let mut current = find_nearest_enemy_spatial(&w.collision, &w.enemies, px, py, WEAPON_SEARCH_RADIUS, &mut w.spatial_query_buf);
    #[allow(unused_assignments)]
    let mut next_search_x = px;
    #[allow(unused_assignments)]
    let mut next_search_y = py;
    for _ in 0..chain_count {
        if let Some(ei) = current {
            let enemy_r = w.params.get_enemy(w.enemies.kind_ids[ei]).radius;
            let hit_x = w.enemies.positions_x[ei] + enemy_r;
            let hit_y = w.enemies.positions_y[ei] + enemy_r;
            w.enemies.hp[ei] -= dmg as f32;
            w.bullets.spawn_effect(hit_x, hit_y, 0.10, BULLET_KIND_LIGHTNING);
            w.particles.emit(hit_x, hit_y, 5, [0.3, 0.8, 1.0, 1.0]);
            if w.enemies.hp[ei] <= 0.0 {
                let kind_e = w.enemies.kind_ids[ei];
                w.enemies.kill(ei);
                w.frame_events.push(FrameEvent::EnemyKilled { enemy_kind: kind_e, x: hit_x, y: hit_y });
            }
            hit_vec.push(ei);
            next_search_x = hit_x;
            next_search_y = hit_y;
            current = find_nearest_enemy_spatial_excluding(
                &w.collision, &w.enemies, next_search_x, next_search_y,
                WEAPON_SEARCH_RADIUS, &hit_vec, &mut w.spatial_query_buf,
            );
        } else {
            break;
        }
    }
    // Chain vs ボス（600px 以内なら連鎖先としてダメージ）
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

fn fire_aura(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    level: u32,
    kind_id: u8,
    cd: f32,
) {
    let radius = w.params.get_weapon(kind_id).aura_radius(level);
    let radius_sq = radius * radius;
    w.collision.dynamic.query_nearby_into(px, py, radius, &mut w.spatial_query_buf);
    for ei in w.spatial_query_buf.iter().copied() {
        if !w.enemies.alive[ei] { continue; }
        let ex = w.enemies.positions_x[ei];
        let ey = w.enemies.positions_y[ei];
        let ddx = ex - px;
        let ddy = ey - py;
        if ddx * ddx + ddy * ddy > radius_sq { continue; }
        w.enemies.hp[ei] -= dmg as f32;
        let kind_e = w.enemies.kind_ids[ei];
        let ep = w.params.get_enemy(kind_e).clone();
        let hit_x = ex + ep.radius;
        let hit_y = ey + ep.radius;
        if w.enemies.hp[ei] <= 0.0 {
            w.enemies.kill(ei);
            w.frame_events.push(FrameEvent::EnemyKilled { enemy_kind: kind_e, x: hit_x, y: hit_y });
            w.particles.emit(hit_x, hit_y, 8, ep.particle_color);
        } else {
            w.particles.emit(hit_x, hit_y, 2, [0.9, 0.9, 0.3, 0.6]);
        }
    }
    w.weapon_slots[si].cooldown_timer = cd;
}
