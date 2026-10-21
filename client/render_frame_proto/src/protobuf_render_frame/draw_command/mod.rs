//! `DrawCommand` protobuf oneof → `shared::DrawCommand`。

use crate::pb;
use shared::render_frame::DrawCommand;

mod kind_gameplay;
mod kind_mesh_3d;
mod kind_scene_3d;
mod kind_sprite;

pub(super) fn draw_cmd_pb(cmd: pb::DrawCommand) -> Option<DrawCommand> {
    use pb::draw_command::Kind::*;
    let k = match cmd.kind {
        Some(k) => k,
        None => {
            log::warn!("protobuf_render_frame: DrawCommand skipped (missing kind)");
            return None;
        }
    };
    Some(match k {
        PlayerSprite(p) => kind_sprite::from_player_sprite(p),
        SpriteRaw(s) => kind_sprite::from_sprite_raw(s),
        Particle(p) => kind_gameplay::from_particle(p),
        Item(i) => kind_gameplay::from_item(i),
        Obstacle(o) => kind_gameplay::from_obstacle(o),
        Box3d(b) => kind_mesh_3d::from_box3d(b),
        Sphere3d(s) => kind_mesh_3d::from_sphere3d(s),
        Cone3d(b) => kind_mesh_3d::from_cone3d(b),
        GridPlane(g) => kind_scene_3d::from_grid_plane(g),
        GridPlaneVerts(g) => kind_scene_3d::from_grid_plane_verts(g),
        Skybox(s) => kind_scene_3d::from_skybox(s),
    })
}
