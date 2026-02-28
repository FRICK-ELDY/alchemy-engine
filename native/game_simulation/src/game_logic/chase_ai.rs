//! Path: native/game_simulation/src/game_logic/chase_ai.rs
//! Summary: 敵 Chase AI と最近接探索（find_nearest_*）

use crate::world::EnemyWorld;
use crate::physics::spatial_hash::CollisionWorld;
use rayon::prelude::*;

/// 最近接の生存敵インデックスを返す
pub fn find_nearest_enemy(enemies: &EnemyWorld, px: f32, py: f32) -> Option<usize> {
    let mut min_dist = f32::MAX;
    let mut nearest  = None;
    for i in 0..enemies.len() {
        if !enemies.alive[i] {
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

/// 指定インデックスを除外した最近接の生存敵インデックスを返す（Lightning チェーン用）
pub fn find_nearest_enemy_excluding(
    enemies: &EnemyWorld,
    px: f32,
    py: f32,
    exclude: &[usize],
) -> Option<usize> {
    let mut min_dist = f32::MAX;
    let mut nearest  = None;
    for i in 0..enemies.len() {
        if !enemies.alive[i] || exclude.contains(&i) {
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

/// 二乗距離（sqrt を避けて高速化）
#[inline]
fn dist_sq(x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    let dx = x1 - x2;
    let dy = y1 - y2;
    dx * dx + dy * dy
}

/// Spatial Hash を使った高速最近接探索
/// search_radius 内に候補がいなければ全探索にフォールバック
pub fn find_nearest_enemy_spatial(
    collision: &CollisionWorld,
    enemies: &EnemyWorld,
    px: f32,
    py: f32,
    search_radius: f32,
    buf: &mut Vec<usize>,
) -> Option<usize> {
    collision.dynamic.query_nearby_into(px, py, search_radius, buf);

    let result = buf
        .iter()
        .filter(|&&i| i < enemies.len() && enemies.alive[i])
        .map(|&i| (i, dist_sq(enemies.positions_x[i], enemies.positions_y[i], px, py)))
        .min_by(|(_, da), (_, db)| da.partial_cmp(db).unwrap_or(std::cmp::Ordering::Equal))
        .map(|(i, _)| i);

    result.or_else(|| find_nearest_enemy(enemies, px, py))
}

/// Spatial Hash を使った高速最近接探索（除外リスト付き・Lightning チェーン用）
pub fn find_nearest_enemy_spatial_excluding(
    collision: &CollisionWorld,
    enemies: &EnemyWorld,
    px: f32,
    py: f32,
    search_radius: f32,
    exclude: &[usize],
    buf: &mut Vec<usize>,
) -> Option<usize> {
    collision.dynamic.query_nearby_into(px, py, search_radius, buf);

    let result = buf
        .iter()
        .filter(|&&i| {
            i < enemies.len()
                && enemies.alive[i]
                && !exclude.contains(&i)
        })
        .map(|&i| (i, dist_sq(enemies.positions_x[i], enemies.positions_y[i], px, py)))
        .min_by(|(_, da), (_, db)| da.partial_cmp(db).unwrap_or(std::cmp::Ordering::Equal))
        .map(|(i, _)| i);

    result.or_else(|| find_nearest_enemy_excluding(enemies, px, py, exclude))
}

/// 1 体分の Chase AI（スカラー版・SIMD フォールバック用）
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

/// SIMD（SSE2）版 Chase AI — x86_64 専用
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

            let alive_mask = _mm_castsi128_ps(_mm_set_epi32(
                if enemies.alive[base + 3] { -1i32 } else { 0 },
                if enemies.alive[base + 2] { -1i32 } else { 0 },
                if enemies.alive[base + 1] { -1i32 } else { 0 },
                if enemies.alive[base + 0] { -1i32 } else { 0 },
            ));

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
            if enemies.alive[i] {
                scalar_chase_one(enemies, i, player_x, player_y, dt);
            }
        }
    }
}

/// Chase AI: 全敵をプレイヤーに向けて移動（rayon で並列化）
pub fn update_chase_ai(enemies: &mut EnemyWorld, player_x: f32, player_y: f32, dt: f32) {
    let len = enemies.len();
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
            if !*is_alive {
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
