use crate::world::GameWorldInner;
use game_core::entity_params::EnemyParams;

/// 1.5.2: 敵が障害物と重なっている場合に押し出す（Ghost はスキップ）
pub(crate) fn resolve_obstacles_enemy(w: &mut GameWorldInner) {
    let collision = &w.collision;
    let buf = &mut w.obstacle_query_buf;
    for i in 0..w.enemies.len() {
        if !w.enemies.alive[i] || EnemyParams::passes_through_obstacles(w.enemies.kind_ids[i]) {
            continue;
        }
        let r = EnemyParams::get(w.enemies.kind_ids[i]).radius;
        let cx = w.enemies.positions_x[i] + r;
        let cy = w.enemies.positions_y[i] + r;
        collision.query_static_nearby_into(cx, cy, r, buf);
        for &idx in buf.iter() {
            if let Some(o) = collision.obstacles.get(idx) {
                let dx = cx - o.x;
                let dy = cy - o.y;
                let dist = (dx * dx + dy * dy).sqrt().max(0.001);
                let overlap = (r + o.radius) - dist;
                if overlap > 0.0 {
                    w.enemies.positions_x[i] += (dx / dist) * overlap;
                    w.enemies.positions_y[i] += (dy / dist) * overlap;
                }
            }
        }
    }
}
