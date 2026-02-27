use crate::world::GameWorldInner;
use game_core::constants::PLAYER_RADIUS;
use game_core::util::spawn_position_around_player;

/// プレイヤー周囲 800〜1200px の円周上にスポーン位置を生成（spawn_enemies / spawn_elite_enemy 共通）
pub(crate) fn get_spawn_positions_around_player(w: &mut GameWorldInner, count: usize) -> Vec<(f32, f32)> {
    let px = w.player.x + PLAYER_RADIUS;
    let py = w.player.y + PLAYER_RADIUS;
    (0..count)
        .map(|_| spawn_position_around_player(&mut w.rng, px, py, 800.0, 1200.0))
        .collect()
}
