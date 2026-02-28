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

/// 指定インデックスを除外した最近接の生存敵インデックスを返す（Lightning チェーン用・最終フォールバック）
/// exclude: &[bool] — インデックス i が true なら除外（O(1) 検索）
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

/// 二乗距離（sqrt を避けて高速化）
#[inline]
fn dist_sq(x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    let dx = x1 - x2;
    let dy = y1 - y2;
    dx * dx + dy * dy
}

/// Spatial Hash を使った高速最近接探索
/// 候補が見つからない場合は半径を 2 倍ずつ最大 4 回拡大して再試行し、
/// それでも見つからない場合のみ O(n) 全探索にフォールバックする（稀なケース）
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

/// Spatial Hash を使った高速最近接探索（除外セット付き・Lightning チェーン用）
/// exclude: &[bool] — インデックス i が true なら除外（O(1) 検索）
/// 候補が見つからない場合は半径を 2 倍ずつ最大 4 回拡大して再試行する
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
    // 全敵が Spatial Hash の範囲外に散らばっている極稀なケース
    find_nearest_enemy_excluding_set(enemies, px, py, exclude)
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

            // alive は Vec<u8>（0xFF=生存, 0x00=死亡）。
            // 4 バイトを u32 として一括ロードし、各バイトレーンを 0xFF と比較して
            // 32 ビット全ビット立ちマスクを生成する（スカラー分岐なし）。
            let alive4_u32 = u32::from_ne_bytes([
                enemies.alive[base],
                enemies.alive[base + 1],
                enemies.alive[base + 2],
                enemies.alive[base + 3],
            ]);
            let alive_bytes = _mm_cvtsi32_si128(alive4_u32 as i32);
            let ff4 = _mm_set1_epi8(-1i8);
            // 各バイトレーンを 0xFF と比較 → 0xFF or 0x00 のバイトマスク
            let byte_mask = _mm_cmpeq_epi8(alive_bytes, ff4);
            // バイトマスクを 32 ビット単位に展開: 各 u8 マスクを i32 全ビットに広げる
            // _mm_unpacklo_epi8 × 2 で byte → word → dword に符号拡張
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

        // 敵はプレイヤー方向（+x）に移動しているべき
        assert!(
            enemies.positions_x[0] > 0.0,
            "敵は +x 方向に移動するべき: x={}",
            enemies.positions_x[0]
        );
        assert!(
            enemies.velocities_x[0] > 0.0,
            "速度 x は正であるべき: vx={}",
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
            "速度の大きさは speed パラメータ (100.0) に等しいべき: {speed:.3}"
        );
    }

    #[test]
    fn find_nearest_enemy_returns_closest() {
        let mut enemies = EnemyWorld::new();
        let ep = make_enemy_params();
        enemies.spawn(&[(10.0, 0.0)], 0, &ep);
        enemies.spawn(&[(50.0, 0.0)], 0, &ep);

        let nearest = find_nearest_enemy(&enemies, 0.0, 0.0);
        assert_eq!(nearest, Some(0), "最近接の敵インデックスは 0 であるべき");
    }

    #[test]
    fn find_nearest_enemy_ignores_dead() {
        let mut enemies = EnemyWorld::new();
        let ep = make_enemy_params();
        enemies.spawn(&[(10.0, 0.0)], 0, &ep);
        enemies.spawn(&[(50.0, 0.0)], 0, &ep);
        enemies.kill(0);

        let nearest = find_nearest_enemy(&enemies, 0.0, 0.0);
        assert_eq!(nearest, Some(1), "死亡した敵は無視されるべき");
    }

    #[test]
    fn find_nearest_enemy_empty_world_returns_none() {
        let enemies = EnemyWorld::new();
        assert_eq!(find_nearest_enemy(&enemies, 0.0, 0.0), None);
    }
}

/// rayon 並列化を適用する最小敵数。
/// これ未満ではスレッドプールのオーバーヘッドがコアロジックを上回るため
/// シングルスレッド版にフォールバックする。
/// ベンチマーク（`cargo bench --bench chase_ai_bench`）で実測して調整すること。
const RAYON_THRESHOLD: usize = 500;

/// Chase AI: 全敵をプレイヤーに向けて移動
/// 敵数が RAYON_THRESHOLD 未満の場合はシングルスレッド版で処理する。
pub fn update_chase_ai(enemies: &mut EnemyWorld, player_x: f32, player_y: f32, dt: f32) {
    let len = enemies.len();

    if len < RAYON_THRESHOLD {
        // シングルスレッド版（少数敵では rayon オーバーヘッドを回避）
        for i in 0..len {
            if enemies.alive[i] == 0 {
                continue;
            }
            let dx   = player_x - enemies.positions_x[i];
            let dy   = player_y - enemies.positions_y[i];
            let dist = (dx * dx + dy * dy).sqrt().max(0.001);
            let speed = enemies.speeds[i];
            enemies.velocities_x[i] = (dx / dist) * speed;
            enemies.velocities_y[i] = (dy / dist) * speed;
            enemies.positions_x[i] += enemies.velocities_x[i] * dt;
            enemies.positions_y[i] += enemies.velocities_y[i] * dt;
        }
        return;
    }

    // rayon 並列版（RAYON_THRESHOLD 以上の敵数）
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
