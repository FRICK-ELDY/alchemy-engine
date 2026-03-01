//! Path: native/game_core/src/physics/obstacle_resolve.rs
//! Summary: プレイヤーと障害物の衝突解決・押し出し処理

use crate::constants::PLAYER_RADIUS;
use super::spatial_hash::CollisionWorld;

/// プレイヤーが障害物と重なっている場合に押し出す（複数障害物対応）
pub fn resolve_obstacles_player(
    collision: &CollisionWorld,
    player_x: &mut f32,
    player_y: &mut f32,
    buf: &mut Vec<usize>,
) {
    for _ in 0..5 {
        let cx = *player_x + PLAYER_RADIUS;
        let cy = *player_y + PLAYER_RADIUS;
        collision.query_static_nearby_into(cx, cy, PLAYER_RADIUS, buf);
        let mut pushed = false;
        for &idx in buf.iter() {
            if let Some(o) = collision.obstacles.get(idx) {
                let dx = cx - o.x;
                let dy = cy - o.y;
                let dist = (dx * dx + dy * dy).sqrt().max(0.001);
                let overlap = (PLAYER_RADIUS + o.radius) - dist;
                if overlap > 0.0 {
                    *player_x += (dx / dist) * overlap;
                    *player_y += (dy / dist) * overlap;
                    pushed = true;
                    break;
                }
            }
        }
        if !pushed {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::physics::spatial_hash::CollisionWorld;

    #[test]
    fn player_pushed_out_of_obstacle() {
        let mut cw = CollisionWorld::new(80.0);
        // 障害物: 中心 (200, 200), 半径 50
        cw.rebuild_static(&[(200.0, 200.0, 50.0, 1)]);

        // プレイヤー中心を障害物中心から少しずらして重ねる
        // px, py はプレイヤーの左上座標。中心は (px + PLAYER_RADIUS, py + PLAYER_RADIUS)
        // 中心を (190, 200) に配置 → 障害物中心との距離 10 < PLAYER_RADIUS(32) + 50 = 82
        let mut px = 190.0 - PLAYER_RADIUS;
        let mut py = 200.0 - PLAYER_RADIUS;
        let mut buf = Vec::new();

        resolve_obstacles_player(&cw, &mut px, &mut py, &mut buf);

        // 解決後、プレイヤー中心と障害物中心の距離 >= PLAYER_RADIUS + obstacle_radius
        let cx = px + PLAYER_RADIUS;
        let cy = py + PLAYER_RADIUS;
        let dist = ((cx - 200.0).powi(2) + (cy - 200.0).powi(2)).sqrt();
        assert!(
            dist >= PLAYER_RADIUS + 50.0 - 0.1,
            "プレイヤーは障害物の外に押し出されるべき: dist={dist:.3}"
        );
    }

    #[test]
    fn player_not_moved_when_no_obstacle() {
        let cw = CollisionWorld::new(80.0);
        let mut px = 0.0_f32;
        let mut py = 0.0_f32;
        let mut buf = Vec::new();

        resolve_obstacles_player(&cw, &mut px, &mut py, &mut buf);

        assert_eq!(px, 0.0);
        assert_eq!(py, 0.0);
    }
}
