//! Path: native/game_physics/src/game_logic/chase_ai.rs
//! Summary: Chase AI (find_nearest_* / update_chase_ai / update_chase_ai_simd)

use crate::world::EnemyWorld;
use crate::physics::spatial_hash::CollisionWorld;
use rayon::prelude::*;

/// ????????????????
pub fn find_nearest_enemy(enemies: &EnemyWorld, px: f32, py: f32) -> Option<usize> {
    let mut min_dist = f32::MAX;
    let mut nearest  = None;
    for i in 0..enemies.len() {
        if enemies.alive[i] == 0 {
            continue;
        }
        let dx   = enemies.positions_x[i] - px;
        let dy   = enemies.positions_y[i] - py;
        let dist = dx * dx + dy * dy;
        if dist < min_dist {
            min_dist = dist;
            nearest  = Some(i);
        }
    }
    nearest
}

/// ??????????????????????????????Lightning ????????????????
fn find_nearest_enemy_excluding_set(
    enemies: &EnemyWorld,
    px: f32,
    py: f32,
    exclude: &[bool],
) -> Option<usize> {
    let mut min_dist = f32::MAX;
    let mut nearest  = None;
    for i in 0..enemies.len() {
        if enemies.alive[i] == 0 || exclude.get(i).copied().unwrap_or(false) {
            continue;
        }
        let dx   = enemies.positions_x[i] - px;
        let dy   = enemies.positions_y[i] - py;
        let dist = dx * dx + dy * dy;
        if dist < min_dist {
            min_dist = dist;
            nearest  = Some(i);
        }
    }
    nearest
}

/// ?????sqrt ????????
#[inline]
fn dist_sq(x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    let dx = x1 - x2;
    let dy = y1 - y2;
    dx * dx + dy * dy
}

/// Spatial Hash ???????????
/// ??????????????? 2 ????? 4 ???????????
/// ?????????????? O(n) ????????????????????
pub fn find_nearest_enemy_spatial(
    collision: &CollisionWorld,
    enemies: &EnemyWorld,
    px: f32,
    py: f32,
    search_radius: f32,
    buf: &mut Vec<usize>,
) -> Option<usize> {
    find_nearest_enemy_spatial_excluding(collision, enemies, px, py, search_radius, &[], buf)
}

/// Spatial Hash ????????????????????Lightning ??????
pub fn find_nearest_enemy_spatial_excluding(
    collision: &CollisionWorld,
    enemies: &EnemyWorld,
    px: f32,
    py: f32,
    search_radius: f32,
    exclude: &[bool],
    buf: &mut Vec<usize>,
) -> Option<usize> {
    let mut radius = search_radius;
    for _ in 0..4 {
        buf.clear();
        collision.dynamic.query_nearby_into(px, py, radius, buf);
        let result = buf
            .iter()
            .filter(|&&i| {
                i < enemies.len()
                    && enemies.alive[i] != 0
                    && !exclude.get(i).copied().unwrap_or(false)
            })
            .map(|&i| (i, dist_sq(enemies.positions_x[i], enemies.positions_y[i], px, py)))
            .min_by(|(_, da), (_, db)| da.partial_cmp(db).unwrap_or(std::cmp::Ordering::Equal))
            .map(|(i, _)| i);
        if result.is_some() {
            return result;
        }
        radius *= 2.0;
    }
    // ??? Spatial Hash ??????????????????
    find_nearest_enemy_excluding_set(enemies, px, py, exclude)
}

/// 1 ??? Chase AI???????SIMD ?????????
#[inline]
fn scalar_chase_one(
    enemies: &mut EnemyWorld,
    i: usize,
    player_x: f32,
    player_y: f32,
    dt: f32,
) {
    let dx = player_x - enemies.positions_x[i];
    let dy = player_y - enemies.positions_y[i];
    let dist = (dx * dx + dy * dy).sqrt().max(0.001);
    let speed = enemies.speeds[i];
    enemies.velocities_x[i] = (dx / dist) * speed;
    enemies.velocities_y[i] = (dy / dist) * speed;
    enemies.positions_x[i] += enemies.velocities_x[i] * dt;
    enemies.positions_y[i] += enemies.velocities_y[i] * dt;
}

/// SIMD (SSE2) Chase AI -- x86_64 only
#[cfg(target_arch = "x86_64")]
pub fn update_chase_ai_simd(
    enemies: &mut EnemyWorld,
    player_x: f32,
    player_y: f32,
    dt: f32,
) {
    use std::arch::x86_64::*;

    let len = enemies.len();
    let simd_len = (len / 4) * 4;

    unsafe {
        let px4 = _mm_set1_ps(player_x);
        let py4 = _mm_set1_ps(player_y);
        let dt4 = _mm_set1_ps(dt);
        let eps4 = _mm_set1_ps(0.001_f32);

        for base in (0..simd_len).step_by(4) {
            let ex = _mm_loadu_ps(enemies.positions_x[base..].as_ptr());
            let ey = _mm_loadu_ps(enemies.positions_y[base..].as_ptr());
            let sp = _mm_loadu_ps(enemies.speeds[base..].as_ptr());

            let dx = _mm_sub_ps(px4, ex);
            let dy = _mm_sub_ps(py4, ey);
            let dist_sq_val = _mm_add_ps(_mm_mul_ps(dx, dx), _mm_mul_ps(dy, dy));
            let dist_sq_safe = _mm_max_ps(dist_sq_val, eps4);
            let inv_dist = _mm_rsqrt_ps(dist_sq_safe);

            let vx = _mm_mul_ps(_mm_mul_ps(dx, inv_dist), sp);
            let vy = _mm_mul_ps(_mm_mul_ps(dy, inv_dist), sp);

            let new_ex = _mm_add_ps(ex, _mm_mul_ps(vx, dt4));
            let new_ey = _mm_add_ps(ey, _mm_mul_ps(vy, dt4));

            // alive is Vec<u8> (0xFF=alive, 0x00=dead).
            // Load 4 bytes as u32, compare each byte lane to 0xFF,
            // then expand to 32-bit mask (no scalar branch).
            let alive4_u32 = u32::from_ne_bytes([
                enemies.alive[base],
                enemies.alive[base + 1],
                enemies.alive[base + 2],
                enemies.alive[base + 3],
            ]);
            let alive_bytes = _mm_cvtsi32_si128(alive4_u32 as i32);
            let ff4 = _mm_set1_epi8(-1i8);
            // Compare each byte lane to 0xFF -> byte mask (0xFF or 0x00)
            let byte_mask = _mm_cmpeq_epi8(alive_bytes, ff4);
            // Expand byte mask to 32-bit lanes: byte -> word -> dword via sign extension
            // _mm_unpacklo_epi8 x2: byte -> word -> dword
            let word_mask  = _mm_unpacklo_epi8(byte_mask, byte_mask);
            let dword_mask = _mm_unpacklo_epi16(word_mask, word_mask);
            let alive_mask = _mm_castsi128_ps(dword_mask);

            let old_vx = _mm_loadu_ps(enemies.velocities_x[base..].as_ptr());
            let old_vy = _mm_loadu_ps(enemies.velocities_y[base..].as_ptr());

            let final_ex = _mm_or_ps(
                _mm_andnot_ps(alive_mask, ex),
                _mm_and_ps(alive_mask, new_ex),
            );
            let final_ey = _mm_or_ps(
                _mm_andnot_ps(alive_mask, ey),
                _mm_and_ps(alive_mask, new_ey),
            );
            let final_vx = _mm_or_ps(
                _mm_andnot_ps(alive_mask, old_vx),
                _mm_and_ps(alive_mask, vx),
            );
            let final_vy = _mm_or_ps(
                _mm_andnot_ps(alive_mask, old_vy),
                _mm_and_ps(alive_mask, vy),
            );

            _mm_storeu_ps(enemies.positions_x[base..].as_mut_ptr(), final_ex);
            _mm_storeu_ps(enemies.positions_y[base..].as_mut_ptr(), final_ey);
            _mm_storeu_ps(enemies.velocities_x[base..].as_mut_ptr(), final_vx);
            _mm_storeu_ps(enemies.velocities_y[base..].as_mut_ptr(), final_vy);
        }

        for i in simd_len..len {
            if enemies.alive[i] != 0 {
                scalar_chase_one(enemies, i, player_x, player_y, dt);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::EnemyWorld;
    use crate::entity_params::EnemyParams;

    fn make_enemy_params() -> EnemyParams {
        EnemyParams {
            max_hp:           100.0,
            speed:            100.0,
            radius:           20.0,
            damage_per_sec:   10.0,
            render_kind:      1,
            particle_color:   [1.0, 0.0, 0.0, 1.0],
            passes_obstacles: false,
        }
    }

    fn spawn_enemy_at(world: &mut EnemyWorld, x: f32, y: f32) {
        let ep = make_enemy_params();
        world.spawn(&[(x, y)], 0, &ep);
    }

    #[test]
    fn update_chase_moves_enemy_toward_player() {
        let mut enemies = EnemyWorld::new();
        spawn_enemy_at(&mut enemies, 0.0, 0.0);

        let player_x = 100.0_f32;
        let player_y = 0.0_f32;
        let dt = 0.016_f32;

        update_chase_ai(&mut enemies, player_x, player_y, dt);

        assert!(
            enemies.positions_x[0] > 0.0,
            "enemy should move toward +x, got x={}",
            enemies.positions_x[0]
        );
        assert!(
            enemies.velocities_x[0] > 0.0,
            "velocity x should be positive, got vx={}",
            enemies.velocities_x[0]
        );
    }

    #[test]
    fn update_chase_velocity_magnitude_equals_speed() {
        let mut enemies = EnemyWorld::new();
        spawn_enemy_at(&mut enemies, 0.0, 0.0);

        let player_x = 100.0_f32;
        let player_y = 100.0_f32;
        let dt = 0.016_f32;

        update_chase_ai(&mut enemies, player_x, player_y, dt);

        let vx = enemies.velocities_x[0];
        let vy = enemies.velocities_y[0];
        let speed = (vx * vx + vy * vy).sqrt();

        assert!(
            (speed - 100.0).abs() < 0.1,
            "speed magnitude should equal speed param (100.0), got {speed:.3}"
        );
    }

    #[test]
    fn find_nearest_enemy_returns_closest() {
        let mut enemies = EnemyWorld::new();
        let ep = make_enemy_params();
        enemies.spawn(&[(10.0, 0.0)], 0, &ep);
        enemies.spawn(&[(50.0, 0.0)], 0, &ep);

        let nearest = find_nearest_enemy(&enemies, 0.0, 0.0);
        assert_eq!(nearest, Some(0), "nearest enemy index should be 0");
    }

    #[test]
    fn find_nearest_enemy_ignores_dead() {
        let mut enemies = EnemyWorld::new();
        let ep = make_enemy_params();
        enemies.spawn(&[(10.0, 0.0)], 0, &ep);
        enemies.spawn(&[(50.0, 0.0)], 0, &ep);
        enemies.kill(0);

        let nearest = find_nearest_enemy(&enemies, 0.0, 0.0);
        assert_eq!(nearest, Some(1), "dead enemy should be ignored");
    }

    #[test]
    fn find_nearest_enemy_empty_world_returns_none() {
        let enemies = EnemyWorld::new();
        assert_eq!(find_nearest_enemy(&enemies, 0.0, 0.0), None);
    }
}

/// Minimum enemy count to apply rayon parallelism.
/// Below this threshold, thread-pool overhead outweighs core logic.
/// Falls back to single-threaded scalar version.
/// Tune via `cargo bench --bench chase_ai_bench`.
const RAYON_THRESHOLD: usize = 500;

/// Chase AI: move all enemies toward the player.
/// Uses single-threaded path when enemy count < RAYON_THRESHOLD.
pub fn update_chase_ai(enemies: &mut EnemyWorld, player_x: f32, player_y: f32, dt: f32) {
    let len = enemies.len();

    if len < RAYON_THRESHOLD {
        for i in 0..len {
            if enemies.alive[i] != 0 {
                scalar_chase_one(enemies, i, player_x, player_y, dt);
            }
        }
        return;
    }

    // rayon parallel path (>= RAYON_THRESHOLD enemies)
    let positions_x  = &mut enemies.positions_x[..len];
    let positions_y  = &mut enemies.positions_y[..len];
    let velocities_x = &mut enemies.velocities_x[..len];
    let velocities_y = &mut enemies.velocities_y[..len];
    let speeds       = &enemies.speeds[..len];
    let alive        = &enemies.alive[..len];

    (
        positions_x,
        positions_y,
        velocities_x,
        velocities_y,
        speeds,
        alive,
    )
        .into_par_iter()
        .for_each(|(px, py, vx, vy, speed, is_alive)| {
            if *is_alive == 0 {
                return;
            }
            let dx   = player_x - *px;
            let dy   = player_y - *py;
            let dist = (dx * dx + dy * dy).sqrt().max(0.001);
            *vx  = (dx / dist) * speed;
            *vy  = (dy / dist) * speed;
            *px += *vx * dt;
            *py += *vy * dt;
        });
}
