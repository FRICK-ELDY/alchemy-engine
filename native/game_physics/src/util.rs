//! Path: native/game_core/src/util.rs
//! Summary: 経験値計算・ウェーブ設定・スポーン位置などの共通ユーティリティ

use crate::constants::WAVES;
use crate::physics::rng::SimpleRng;

/// 経過時間に応じた現在のウェーブ設定を返す (interval_secs, count_per_tick)
#[allow(dead_code)] // main スタンドアロンのみで使用
pub fn current_wave(elapsed_secs: f32) -> (f32, usize) {
    WAVES.iter()
        .filter(|&&(start, _, _)| elapsed_secs >= start)
        .last()
        .map(|&(_, interval, count)| (interval, count))
        .unwrap_or((0.8, 20))
}

/// エリート敵スポーン判定（10分以降に 20% で出現、main スタンドアロン用）
#[allow(dead_code)] // main スタンドアロンのみで使用
pub fn is_elite_spawn(elapsed_secs: f32, rng: &mut SimpleRng) -> bool {
    elapsed_secs >= 600.0 && rng.next_u32() % 5 == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_current_wave() {
        let (interval, count) = current_wave(0.0);
        assert!((interval - 4.0).abs() < 0.001);
        assert_eq!(count, 2);
        let (i2, c2) = current_wave(600.0);
        assert_eq!(c2, 18);
        assert!((i2 - 0.7).abs() < 0.001);
    }

    #[test]
    fn test_is_elite_spawn_before_600() {
        let mut rng = SimpleRng::new(12345);
        assert!(!is_elite_spawn(599.0, &mut rng));
    }
}

/// 画面外の四辺いずれかにランダムに配置（マップ端からスポーン）
#[allow(dead_code)] // 互換性のため残す
pub fn spawn_position_outside(rng: &mut SimpleRng, map_width: f32, map_height: f32) -> (f32, f32) {
    let margin = 80.0;
    match rng.next_u32() % 4 {
        0 => (rng.next_f32() * map_width, -margin),
        1 => (rng.next_f32() * map_width, map_height + margin),
        2 => (-margin, rng.next_f32() * map_height),
        _ => (map_width + margin, rng.next_f32() * map_height),
    }
}

/// プレイヤー周囲の円周上に配置（SPEC: 800〜1200px の円周上・画面外）
/// 敵がプレイヤーから見つけやすい距離にスポーンする
pub fn spawn_position_around_player(
    rng: &mut SimpleRng,
    player_x: f32,
    player_y: f32,
    min_dist: f32,
    max_dist: f32,
) -> (f32, f32) {
    let angle = rng.next_f32() * std::f32::consts::TAU;
    let dist = min_dist + rng.next_f32() * (max_dist - min_dist);
    (
        player_x + angle.cos() * dist,
        player_y + angle.sin() * dist,
    )
}
