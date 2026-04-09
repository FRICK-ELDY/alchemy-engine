//! `Particle` / `Item` / `Obstacle`。

use crate::pb;
use shared::render_frame::DrawCommand;

use super::super::u32_to_u8_clamped;

pub(super) fn from_particle(p: pb::ParticleCmd) -> DrawCommand {
    DrawCommand::Particle {
        x: p.x,
        y: p.y,
        r: p.r,
        g: p.g,
        b: p.b,
        alpha: p.alpha,
        size: p.size,
    }
}

pub(super) fn from_item(i: pb::ItemCmd) -> DrawCommand {
    DrawCommand::Item {
        x: i.x,
        y: i.y,
        kind: u32_to_u8_clamped("item.kind", i.kind),
    }
}

pub(super) fn from_obstacle(o: pb::ObstacleCmd) -> DrawCommand {
    DrawCommand::Obstacle {
        x: o.x,
        y: o.y,
        radius: o.radius,
        kind: u32_to_u8_clamped("obstacle.kind", o.kind),
    }
}
