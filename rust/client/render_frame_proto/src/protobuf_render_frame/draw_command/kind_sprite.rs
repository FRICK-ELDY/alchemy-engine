//! `PlayerSprite` / `SpriteRaw`。

use crate::pb;
use shared::render_frame::DrawCommand;

use super::super::float_helpers::{f2, f4};
use super::super::u32_to_u8_clamped;

pub(super) fn from_player_sprite(p: pb::PlayerSprite) -> DrawCommand {
    DrawCommand::PlayerSprite {
        x: p.x,
        y: p.y,
        frame: u32_to_u8_clamped("player_sprite.frame", p.frame),
    }
}

pub(super) fn from_sprite_raw(s: pb::SpriteRaw) -> DrawCommand {
    DrawCommand::SpriteRaw {
        x: s.x,
        y: s.y,
        width: s.width,
        height: s.height,
        uv_offset: f2(&s.uv_offset),
        uv_size: f2(&s.uv_size),
        color_tint: f4(&s.color_tint),
    }
}
