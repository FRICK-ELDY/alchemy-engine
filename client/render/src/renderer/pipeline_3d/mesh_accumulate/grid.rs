//! グリッド地面（`GridPlane` / `GridPlaneVerts`）。

use crate::DrawCommand;
use crate::MeshVertex;

use super::super::mesh_template::grid_lines;

pub(super) fn accumulate(cmd: &DrawCommand, grid_verts_scratch: &mut Vec<MeshVertex>) -> bool {
    match cmd {
        DrawCommand::GridPlaneVerts { vertices } => {
            grid_verts_scratch.extend(vertices.iter().copied());
            true
        }
        DrawCommand::GridPlane {
            size,
            divisions,
            color,
        } => {
            grid_lines(*size, *divisions, *color, grid_verts_scratch);
            true
        }
        _ => false,
    }
}
