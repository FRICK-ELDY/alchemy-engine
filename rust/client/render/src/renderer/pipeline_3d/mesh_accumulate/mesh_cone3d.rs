//! `DrawCommand::Cone3D` → `unit_cone` テンプレート展開。

use crate::DrawCommand;
use crate::MeshVertex;
use std::collections::HashMap;

use super::super::mesh_template::push_mesh_from_def;

pub(super) fn accumulate(
    cmd: &DrawCommand,
    mesh_def_cache: &HashMap<String, (Vec<MeshVertex>, Vec<u32>)>,
    mesh_verts_scratch: &mut Vec<MeshVertex>,
    mesh_indices_scratch: &mut Vec<u32>,
) -> bool {
    let DrawCommand::Cone3D {
        x,
        y,
        z,
        half_w,
        half_h,
        half_d,
        color,
    } = cmd
    else {
        return false;
    };
    push_mesh_from_def(
        mesh_def_cache,
        "unit_cone",
        *x,
        *y,
        *z,
        *half_w,
        *half_h,
        *half_d,
        *color,
        mesh_verts_scratch,
        mesh_indices_scratch,
    );
    true
}
