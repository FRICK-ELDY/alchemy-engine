use crate::constants::PLAYER_RADIUS;
use crate::util::spawn_position_around_player;
use crate::world::GameWorldInner;

/// プレイヤー周囲 800〜1200px の円周上にスポーン位置を生成（spawn_enemies / spawn_elite_enemy 共通）
pub fn get_spawn_positions_around_player(w: &mut GameWorldInner, count: usize) -> Vec<(f32, f32)> {
    let px = w.player.x + PLAYER_RADIUS;
    let py = w.player.y + PLAYER_RADIUS;
    (0..count)
        .map(|_| spawn_position_around_player(&mut w.rng, px, py, 800.0, 1200.0))
        .collect()
}
