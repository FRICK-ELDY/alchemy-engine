use crate::constants::{MAX_ENEMIES, WEAPON_SEARCH_RADIUS};
use crate::entity_params::FirePattern;
use crate::game_logic::{find_nearest_enemy_spatial, find_nearest_enemy_spatial_excluding};
use crate::world::{
    FrameEvent, GameWorldInner, BULLET_KIND_LIGHTNING, BULLET_KIND_WHIP, DEFAULT_BULLET_HIT_COLOR,
    DEFAULT_PIERCING_HIT_COLOR,
};

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

    let slot_count = w.weapon_slots_input.len();
    for si in 0..slot_count {
        w.weapon_slots_input[si].cooldown_timer =
            (w.weapon_slots_input[si].cooldown_timer - dt).max(0.0);
        if w.weapon_slots_input[si].cooldown_timer > 0.0 {
            continue;
        }

        let kind_id = w.weapon_slots_input[si].kind_id;
        let Some(wp) = w.params.get_weapon(kind_id) else {
            continue;
        };
        let cd = w.weapon_slots_input[si].cooldown_sec;
        let dmg = w.weapon_slots_input[si].precomputed_damage;
        let level = w.weapon_slots_input[si].level;
        let bcount = w.weapon_slots_input[si].bullet_count(wp);
        let pattern = wp.fire_pattern;

        let hit_color = wp.hit_particle_color.unwrap_or(DEFAULT_BULLET_HIT_COLOR);
        let piercing_hit_color = wp.hit_particle_color.unwrap_or(DEFAULT_PIERCING_HIT_COLOR);
        match pattern {
            FirePattern::Aimed => fire_aimed(
                w,
                si,
                px,
                py,
                dmg,
                bcount,
                cd,
                wp.aimed_spread_rad,
                hit_color,
            ),
            FirePattern::FixedUp => fire_fixed_up(w, si, px, py, dmg, cd, hit_color),
            FirePattern::Radial => fire_radial(w, si, px, py, dmg, level, kind_id, cd, hit_color),
            FirePattern::Whip => fire_whip(w, si, px, py, dmg, level, kind_id, cd, facing_angle),
            FirePattern::Piercing => fire_piercing(w, si, px, py, dmg, cd, piercing_hit_color),
            FirePattern::Chain => fire_chain(w, si, px, py, dmg, level, kind_id, cd),
            FirePattern::Aura => fire_aura(w, si, px, py, dmg, level, kind_id, cd),
        }
    }

    for si in 0..slot_count {
        w.frame_events.push(FrameEvent::WeaponCooldownUpdated {
            kind_id: w.weapon_slots_input[si].kind_id,
            cooldown_timer: w.weapon_slots_input[si].cooldown_timer,
        });
    }
}

#[allow(clippy::too_many_arguments)]
fn fire_aimed(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    bcount: usize,
    cd: f32,
    spread_rad: f32,
    hit_color: [f32; 4],
) {
    if let Some(ti) = find_nearest_enemy_spatial(
        &w.collision,
        &w.enemies,
        px,
        py,
        WEAPON_SEARCH_RADIUS,
        &mut w.spatial_query_buf,
    ) {
        let target_r = w
            .params
            .get_enemy(w.enemies.kind_ids[ti])
            .map(|e| e.radius)
            .unwrap_or_else(|| w.params.effective_default_enemy_radius());
        let tx = w.enemies.positions_x[ti] + target_r;
        let ty = w.enemies.positions_y[ti] + target_r;
        let base_angle = (ty - py).atan2(tx - px);
        let spread = spread_rad;
        let half = (bcount as f32 - 1.0) / 2.0;
        for bi in 0..bcount {
            let angle = base_angle + (bi as f32 - half) * spread;
            let vx = angle.cos() * w.bullet_speed;
            let vy = angle.sin() * w.bullet_speed;
            w.bullets.spawn_with_hit_color(
                px,
                py,
                vx,
                vy,
                dmg,
                w.bullet_lifetime,
                false,
                crate::world::BULLET_KIND_NORMAL,
                hit_color,
            );
        }
        w.weapon_slots_input[si].cooldown_timer = cd;
    }
}

fn fire_fixed_up(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    cd: f32,
    hit_color: [f32; 4],
) {
    w.bullets.spawn_with_hit_color(
        px,
        py,
        0.0,
        -w.bullet_speed,
        dmg,
        w.bullet_lifetime,
        false,
        crate::world::BULLET_KIND_NORMAL,
        hit_color,
    );
    w.weapon_slots_input[si].cooldown_timer = cd;
}

#[allow(clippy::too_many_arguments)]
fn fire_radial(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    level: u32,
    kind_id: u8,
    cd: f32,
    hit_color: [f32; 4],
) {
    let dir_count = w
        .params
        .get_weapon(kind_id)
        .map(|wp| wp.radial_dir_count(level))
        .unwrap_or(4);
    let dirs_4: [(f32, f32); 4] = [(0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)];
    let diag = std::f32::consts::FRAC_1_SQRT_2;
    let dirs_8: [(f32, f32); 8] = [
        (0.0, -1.0),
        (0.0, 1.0),
        (-1.0, 0.0),
        (1.0, 0.0),
        (diag, -diag),
        (-diag, -diag),
        (diag, diag),
        (-diag, diag),
    ];
    let dirs: &[(f32, f32)] = if dir_count >= 8 { &dirs_8 } else { &dirs_4 };
    for &(dx_dir, dy_dir) in dirs {
        w.bullets.spawn_with_hit_color(
            px,
            py,
            dx_dir * w.bullet_speed,
            dy_dir * w.bullet_speed,
            dmg,
            w.bullet_lifetime,
            false,
            crate::world::BULLET_KIND_NORMAL,
            hit_color,
        );
    }
    w.weapon_slots_input[si].cooldown_timer = cd;
}

#[allow(clippy::too_many_arguments)]
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
    let wp = w.params.get_weapon(kind_id);
    let whip_hit_color = wp
        .and_then(|p| p.hit_particle_color)
        .unwrap_or([1.0, 0.6, 0.1, 1.0]);
    // wp が None の場合は params 未ロードなどの異常系。フォールバックで最低限動作させる。
    let range = wp
        .map(|p| p.whip_range(level))
        .unwrap_or_else(|| w.params.effective_default_whip_range());
    let whip_half_angle = wp.map(|p| p.whip_half_angle_rad).unwrap_or(0.0);
    let effect_lifetime = wp.map(|p| p.effect_lifetime_sec).unwrap_or(0.0);
    if range <= 0.0 {
        log::warn!(
            "Whip weapon kind_id={} has no whip_range_per_level or empty table — weapon will not hit",
            kind_id
        );
    }
    if whip_half_angle <= 0.0 && wp.is_some() {
        log::warn!(
            "Whip weapon kind_id={} has whip_half_angle_rad=0 — cone check will never pass",
            kind_id
        );
    }
    let eff_x = px + facing_angle.cos() * range * 0.5;
    let eff_y = py + facing_angle.sin() * range * 0.5;
    w.bullets
        .spawn_effect(eff_x, eff_y, effect_lifetime, BULLET_KIND_WHIP);
    let whip_range_sq = range * range;
    w.collision
        .dynamic
        .query_nearby_into(px, py, range, &mut w.spatial_query_buf);
    for ei in w.spatial_query_buf.iter().copied() {
        if w.enemies.alive[ei] == 0 {
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
        let diff = (angle - facing_angle + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU)
            - std::f32::consts::PI;
        if diff.abs() < whip_half_angle {
            let enemy_r = w
                .params
                .get_enemy(w.enemies.kind_ids[ei])
                .map(|e| e.radius)
                .unwrap_or_else(|| w.params.effective_default_enemy_radius());
            let hit_x = ex + enemy_r;
            let hit_y = ey + enemy_r;
            w.enemies.hp[ei] -= dmg as f32;
            if w.enemies.hp[ei] <= 0.0 {
                let kind_e = w.enemies.kind_ids[ei];
                let particle_color = w
                    .params
                    .get_enemy(kind_e)
                    .map(|e| e.particle_color)
                    .unwrap_or_else(|| w.params.effective_default_particle_color());
                w.enemies.kill(ei);
                w.frame_events.push(FrameEvent::EnemyKilled {
                    enemy_kind: kind_e,
                    x: hit_x,
                    y: hit_y,
                });
                w.particles.emit(hit_x, hit_y, 8, particle_color);
            } else {
                w.particles.emit(hit_x, hit_y, 3, whip_hit_color);
            }
        }
    }
    // Whip vs 特殊エンティティ（スナップショット）
    {
        let special_hit: Option<(f32, f32)> = if let Some(ref snap) = w.special_entity_snapshot {
            if !snap.invincible {
                let ddx = snap.x - px;
                let ddy = snap.y - py;
                if ddx * ddx + ddy * ddy <= whip_range_sq {
                    let angle = ddy.atan2(ddx);
                    let diff = (angle - facing_angle + std::f32::consts::PI)
                        .rem_euclid(std::f32::consts::TAU)
                        - std::f32::consts::PI;
                    if diff.abs() < whip_half_angle {
                        Some((snap.x, snap.y))
                    } else {
                        None
                    }
                } else {
                    None
                }
            } else {
                None
            }
        } else {
            None
        };
        if let Some((bx, by)) = special_hit {
            w.frame_events
                .push(FrameEvent::SpecialEntityDamaged { damage: dmg as f32 });
            w.particles.emit(bx, by, 4, whip_hit_color);
        }
    }
    w.weapon_slots_input[si].cooldown_timer = cd;
}

fn fire_piercing(
    w: &mut GameWorldInner,
    si: usize,
    px: f32,
    py: f32,
    dmg: i32,
    cd: f32,
    hit_color: [f32; 4],
) {
    if let Some(ti) = find_nearest_enemy_spatial(
        &w.collision,
        &w.enemies,
        px,
        py,
        WEAPON_SEARCH_RADIUS,
        &mut w.spatial_query_buf,
    ) {
        let target_r = w
            .params
            .get_enemy(w.enemies.kind_ids[ti])
            .map(|e| e.radius)
            .unwrap_or_else(|| w.params.effective_default_enemy_radius());
        let tx = w.enemies.positions_x[ti] + target_r;
        let ty = w.enemies.positions_y[ti] + target_r;
        let base_angle = (ty - py).atan2(tx - px);
        let vx = base_angle.cos() * w.bullet_speed;
        let vy = base_angle.sin() * w.bullet_speed;
        w.bullets.spawn_with_hit_color(
            px,
            py,
            vx,
            vy,
            dmg,
            w.bullet_lifetime,
            true,
            crate::world::BULLET_KIND_FIREBALL,
            hit_color,
        );
        w.weapon_slots_input[si].cooldown_timer = cd;
    }
}

#[allow(clippy::too_many_arguments)]
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
    let wp_chain = w.params.get_weapon(kind_id);
    let chain_count = wp_chain
        .map(|wp| wp.chain_count_for_level(level))
        .unwrap_or_else(|| w.params.effective_default_chain_count());
    let chain_effect_lifetime = wp_chain.map(|p| p.effect_lifetime_sec).unwrap_or(0.0);
    let chain_hit_color = wp_chain
        .and_then(|p| p.hit_particle_color)
        .unwrap_or([0.3, 0.8, 1.0, 1.0]);
    if chain_count == 0 {
        log::warn!(
            "Chain weapon kind_id={} has no chain_count_per_level or empty table — chain will not fire",
            kind_id
        );
    }
    // 命中済み敵インデックスを O(1) で検索するためビットマスク配列を使用（300 バイト）
    let mut hit_set = [false; MAX_ENEMIES];
    let mut current = find_nearest_enemy_spatial(
        &w.collision,
        &w.enemies,
        px,
        py,
        WEAPON_SEARCH_RADIUS,
        &mut w.spatial_query_buf,
    );
    #[allow(unused_assignments)]
    let mut next_search_x = px;
    #[allow(unused_assignments)]
    let mut next_search_y = py;
    for _ in 0..chain_count {
        if let Some(ei) = current {
            let enemy_r = w
                .params
                .get_enemy(w.enemies.kind_ids[ei])
                .map(|e| e.radius)
                .unwrap_or_else(|| w.params.effective_default_enemy_radius());
            let hit_x = w.enemies.positions_x[ei] + enemy_r;
            let hit_y = w.enemies.positions_y[ei] + enemy_r;
            w.enemies.hp[ei] -= dmg as f32;
            w.bullets
                .spawn_effect(hit_x, hit_y, chain_effect_lifetime, BULLET_KIND_LIGHTNING);
            w.particles.emit(hit_x, hit_y, 5, chain_hit_color);
            if w.enemies.hp[ei] <= 0.0 {
                let kind_e = w.enemies.kind_ids[ei];
                w.enemies.kill(ei);
                w.frame_events.push(FrameEvent::EnemyKilled {
                    enemy_kind: kind_e,
                    x: hit_x,
                    y: hit_y,
                });
            }
            if ei < MAX_ENEMIES {
                hit_set[ei] = true;
            }
            next_search_x = hit_x;
            next_search_y = hit_y;
            current = find_nearest_enemy_spatial_excluding(
                &w.collision,
                &w.enemies,
                next_search_x,
                next_search_y,
                WEAPON_SEARCH_RADIUS,
                &hit_set,
                &mut w.spatial_query_buf,
            );
        } else {
            break;
        }
    }
    // Chain vs 特殊エンティティ（600px 以内なら連鎖先としてダメージ）
    {
        let special_hit: Option<(f32, f32)> = if let Some(ref snap) = w.special_entity_snapshot {
            if !snap.invincible {
                let ddx = snap.x - px;
                let ddy = snap.y - py;
                let r = w.chain_boss_range;
                if ddx * ddx + ddy * ddy < r * r {
                    Some((snap.x, snap.y))
                } else {
                    None
                }
            } else {
                None
            }
        } else {
            None
        };
        if let Some((bx, by)) = special_hit {
            w.frame_events
                .push(FrameEvent::SpecialEntityDamaged { damage: dmg as f32 });
            w.bullets
                .spawn_effect(bx, by, chain_effect_lifetime, BULLET_KIND_LIGHTNING);
            w.particles.emit(bx, by, 5, chain_hit_color);
        }
    }
    w.weapon_slots_input[si].cooldown_timer = cd;
}

#[allow(clippy::too_many_arguments)]
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
    let wp_aura = w.params.get_weapon(kind_id);
    let radius = wp_aura
        .map(|wp| wp.aura_radius(level))
        .unwrap_or_else(|| w.params.effective_default_aura_radius());
    let aura_hit_color = wp_aura
        .and_then(|p| p.hit_particle_color)
        .unwrap_or([0.9, 0.9, 0.3, 0.6]);
    if radius <= 0.0 {
        log::warn!(
            "Aura weapon kind_id={} has no aura_radius_per_level or empty table — weapon will not hit",
            kind_id
        );
    }
    let radius_sq = radius * radius;
    w.collision
        .dynamic
        .query_nearby_into(px, py, radius, &mut w.spatial_query_buf);
    for ei in w.spatial_query_buf.iter().copied() {
        if w.enemies.alive[ei] == 0 {
            continue;
        }
        let ex = w.enemies.positions_x[ei];
        let ey = w.enemies.positions_y[ei];
        let ddx = ex - px;
        let ddy = ey - py;
        if ddx * ddx + ddy * ddy > radius_sq {
            continue;
        }
        w.enemies.hp[ei] -= dmg as f32;
        let kind_e = w.enemies.kind_ids[ei];
        let (enemy_r, particle_color) = w
            .params
            .get_enemy(kind_e)
            .map(|e| (e.radius, e.particle_color))
            .unwrap_or_else(|| {
                (
                    w.params.effective_default_enemy_radius(),
                    w.params.effective_default_particle_color(),
                )
            });
        let hit_x = ex + enemy_r;
        let hit_y = ey + enemy_r;
        if w.enemies.hp[ei] <= 0.0 {
            w.enemies.kill(ei);
            w.frame_events.push(FrameEvent::EnemyKilled {
                enemy_kind: kind_e,
                x: hit_x,
                y: hit_y,
            });
            w.particles.emit(hit_x, hit_y, 8, particle_color);
        } else {
            w.particles.emit(hit_x, hit_y, 2, aura_hit_color);
        }
    }
    w.weapon_slots_input[si].cooldown_timer = cd;
}
