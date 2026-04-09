//! 3D パス用: グリッド・メッシュテンプレート（`Box3D` / `Sphere3D` / `Cone3D` 等）を CPU スクラッチへ積む。

mod grid;
mod mesh_box3d;
mod mesh_cone3d;
mod mesh_sphere3d;

use crate::DrawCommand;
use crate::MeshVertex;
use std::collections::HashMap;

/// スカイボックス以外の幾何をコマンド列からスクラッチへ書き込む（毎フレーム先に `clear` 済みであること）。
pub(super) fn accumulate_grid_and_mesh_draws(
    commands: &[DrawCommand],
    mesh_def_cache: &HashMap<String, (Vec<MeshVertex>, Vec<u32>)>,
    grid_verts_scratch: &mut Vec<MeshVertex>,
    mesh_verts_scratch: &mut Vec<MeshVertex>,
    mesh_indices_scratch: &mut Vec<u32>,
) {
    for cmd in commands {
        if grid::accumulate(cmd, grid_verts_scratch) {
            continue;
        }
        if mesh_box3d::accumulate(
            cmd,
            mesh_def_cache,
            mesh_verts_scratch,
            mesh_indices_scratch,
        ) {
            continue;
        }
        if mesh_sphere3d::accumulate(
            cmd,
            mesh_def_cache,
            mesh_verts_scratch,
            mesh_indices_scratch,
        ) {
            continue;
        }
        if mesh_cone3d::accumulate(
            cmd,
            mesh_def_cache,
            mesh_verts_scratch,
            mesh_indices_scratch,
        ) {
            continue;
        }
    }
}
