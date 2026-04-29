//! 3D パス用: グリッド・メッシュテンプレート（`Box3D` / `Sphere3D` / `Cone3D` 等）を CPU スクラッチへ積む。
//!
//! グリッドは [`grid`] に分離し、メッシュ系は本モジュール内の `match` に集約する。

mod grid;

use crate::DrawCommand;
use crate::MeshVertex;
use std::collections::HashMap;

use super::mesh_template::{push_mesh_from_def, MeshFromDefInst};

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
                    MeshFromDefInst {
                        x: *x,
                        y: *y,
                        z: *z,
                        half_w: *half_w,
                        half_h: *half_h,
                        half_d: *half_d,
                        color: *color,
                    },
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
                    MeshFromDefInst {
                        x: *x,
                        y: *y,
                        z: *z,
                        half_w: *radius,
                        half_h: *radius,
                        half_d: *radius,
                        color: *color,
                    },
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
                    MeshFromDefInst {
                        x: *x,
                        y: *y,
                        z: *z,
                        half_w: *half_w,
                        half_h: *half_h,
                        half_d: *half_d,
                        color: *color,
                    },
                    mesh_verts_scratch,
                    mesh_indices_scratch,
                );
            }
            _ => {}
        }
    }
}
