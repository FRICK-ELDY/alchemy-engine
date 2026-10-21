//! `Box3d` / `Sphere3d` / `Cone3d`（メッシュテンプレート用 3D 図形）。

use crate::pb;
use shared::render_frame::DrawCommand;

use super::super::float_helpers::f4;

pub(super) fn from_box3d(b: pb::Box3dCmd) -> DrawCommand {
    DrawCommand::Box3D {
        x: b.x,
        y: b.y,
        z: b.z,
        half_w: b.half_w,
        half_h: b.half_h,
        half_d: b.half_d,
        color: f4(&b.color),
    }
}

pub(super) fn from_sphere3d(s: pb::Sphere3dCmd) -> DrawCommand {
    DrawCommand::Sphere3D {
        x: s.x,
        y: s.y,
        z: s.z,
        radius: s.radius,
        color: f4(&s.color),
    }
}

pub(super) fn from_cone3d(b: pb::Box3dCmd) -> DrawCommand {
    DrawCommand::Cone3D {
        x: b.x,
        y: b.y,
        z: b.z,
        half_w: b.half_w,
        half_h: b.half_h,
        half_d: b.half_d,
        color: f4(&b.color),
    }
}
