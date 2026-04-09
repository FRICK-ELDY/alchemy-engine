//! `DrawCommand` protobuf oneof → `shared::DrawCommand`。

use crate::pb;
use shared::render_frame::DrawCommand;

use super::float_helpers::{f2, f4};
use super::mesh_helpers::mesh_vertex_pb;
use super::u32_to_u8_clamped;

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
        PlayerSprite(p) => DrawCommand::PlayerSprite {
            x: p.x,
            y: p.y,
            frame: u32_to_u8_clamped("player_sprite.frame", p.frame),
        },
        SpriteRaw(s) => DrawCommand::SpriteRaw {
            x: s.x,
            y: s.y,
            width: s.width,
            height: s.height,
            uv_offset: f2(&s.uv_offset),
            uv_size: f2(&s.uv_size),
            color_tint: f4(&s.color_tint),
        },
        Particle(p) => DrawCommand::Particle {
            x: p.x,
            y: p.y,
            r: p.r,
            g: p.g,
            b: p.b,
            alpha: p.alpha,
            size: p.size,
        },
        Item(i) => DrawCommand::Item {
            x: i.x,
            y: i.y,
            kind: u32_to_u8_clamped("item.kind", i.kind),
        },
        Obstacle(o) => DrawCommand::Obstacle {
            x: o.x,
            y: o.y,
            radius: o.radius,
            kind: u32_to_u8_clamped("obstacle.kind", o.kind),
        },
        Box3d(b) => DrawCommand::Box3D {
            x: b.x,
            y: b.y,
            z: b.z,
            half_w: b.half_w,
            half_h: b.half_h,
            half_d: b.half_d,
            color: f4(&b.color),
        },
        Sphere3d(s) => DrawCommand::Sphere3D {
            x: s.x,
            y: s.y,
            z: s.z,
            radius: s.radius,
            color: f4(&s.color),
        },
        Cone3d(b) => DrawCommand::Cone3D {
            x: b.x,
            y: b.y,
            z: b.z,
            half_w: b.half_w,
            half_h: b.half_h,
            half_d: b.half_d,
            color: f4(&b.color),
        },
        GridPlane(g) => DrawCommand::GridPlane {
            size: g.size,
            divisions: g.divisions,
            color: f4(&g.color),
        },
        GridPlaneVerts(g) => DrawCommand::GridPlaneVerts {
            vertices: g.vertices.into_iter().map(mesh_vertex_pb).collect(),
        },
        Skybox(s) => DrawCommand::Skybox {
            top_color: f4(&s.top_color),
            bottom_color: f4(&s.bottom_color),
        },
    })
}
