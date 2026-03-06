use crate::constants::PLAYER_RADIUS;
use crate::util::spawn_position_around_player;
use crate::world::GameWorldInner;

/// プレイヤー周囲 spawn_min_dist〜spawn_max_dist px の円周上にスポーン位置を生成。
/// R-S1: min/max は set_world_params で注入可能（デフォルト 800, 1200）。
pub fn get_spawn_positions_around_player(w: &mut GameWorldInner, count: usize) -> Vec<(f32, f32)> {
    let px = w.player.x + PLAYER_RADIUS;
    let py = w.player.y + PLAYER_RADIUS;
    (0..count)
        .map(|_| {
            spawn_position_around_player(
                &mut w.rng,
                px,
                py,
                w.spawn_min_dist,
                w.spawn_max_dist,
            )
        })
        .collect()
}
