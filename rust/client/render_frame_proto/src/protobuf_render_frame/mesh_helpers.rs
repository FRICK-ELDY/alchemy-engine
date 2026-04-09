use crate::pb;
use shared::render_frame::{MeshDef, MeshVertex};

use super::float_helpers::f4;

pub(super) fn mesh_vertex_pb(v: pb::MeshVertex) -> MeshVertex {
    let p = &v.position;
    let c = &v.color;
    MeshVertex {
        position: [
            p.first().copied().unwrap_or(0.0),
            p.get(1).copied().unwrap_or(0.0),
            p.get(2).copied().unwrap_or(0.0),
        ],
        color: f4(c),
    }
}

pub(super) fn mesh_def_pb(m: pb::MeshDef) -> MeshDef {
    MeshDef {
        name: m.name,
        vertices: m.vertices.into_iter().map(mesh_vertex_pb).collect(),
        indices: m.indices,
    }
}
