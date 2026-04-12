//! 3D パス用: グリッド・メッシュテンプレート（`Box3D` / `Sphere3D` / `Cone3D` 等）を CPU スクラッチへ積む。
//!
//! グリッドは [`grid`] に分離し、メッシュ系は本モジュール内の `match` に集約する。

mod grid;

use crate::DrawCommand;
use crate::MeshVertex;
use std::collections::HashMap;

use super::mesh_template::push_mesh_from_def;

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

        match cmd {
            DrawCommand::Box3D {
                x,
                y,
                z,
                half_w,
                half_h,
                half_d,
                color,
            } => {
                push_mesh_from_def(
                    mesh_def_cache,
                    "unit_box",
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
            }
            DrawCommand::Sphere3D {
                x,
                y,
                z,
                radius,
                color,
            } => {
                push_mesh_from_def(
                    mesh_def_cache,
                    "unit_sphere",
                    *x,
                    *y,
                    *z,
                    *radius,
                    *radius,
                    *radius,
                    *color,
                    mesh_verts_scratch,
                    mesh_indices_scratch,
                );
            }
            DrawCommand::Cone3D {
                x,
                y,
                z,
                half_w,
                half_h,
                half_d,
                color,
            } => {
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
            }
            _ => {}
        }
    }
}
