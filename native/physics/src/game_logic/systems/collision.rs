use crate::entity_params::DEFAULT_ENEMY_RADIUS;
use crate::world::GameWorldInner;

/// 1.5.2: 敵が障害物と重なっている場合に押し出す（Ghost はスキップ）
pub(crate) fn resolve_obstacles_enemy(w: &mut GameWorldInner) {
    let collision = &w.collision;
    let buf = &mut w.obstacle_query_buf;
    for i in 0..w.enemies.len() {
        if w.enemies.alive[i] == 0 || w.params.enemy_passes_obstacles(w.enemies.kind_ids[i]) {
            continue;
        }
        let r = w
            .params
            .get_enemy(w.enemies.kind_ids[i])
            .map(|ep| ep.radius)
            .unwrap_or(DEFAULT_ENEMY_RADIUS);
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
