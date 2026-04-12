//! `GridPlane` / `GridPlaneVerts` / `Skybox`。

use crate::pb;
use shared::render_frame::DrawCommand;

use super::super::float_helpers::f4;
use super::super::mesh_helpers::mesh_vertex_pb;

pub(super) fn from_grid_plane(g: pb::GridPlaneCmd) -> DrawCommand {
    DrawCommand::GridPlane {
        size: g.size,
        divisions: g.divisions,
        color: f4(&g.color),
    }
}

pub(super) fn from_grid_plane_verts(g: pb::GridPlaneVertsCmd) -> DrawCommand {
    DrawCommand::GridPlaneVerts {
        vertices: g.vertices.into_iter().map(mesh_vertex_pb).collect(),
    }
}

pub(super) fn from_skybox(s: pb::SkyboxCmd) -> DrawCommand {
    DrawCommand::Skybox {
        top_color: f4(&s.top_color),
        bottom_color: f4(&s.bottom_color),
    }
}
