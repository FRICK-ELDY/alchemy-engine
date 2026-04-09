//! プロシージャルメッシュ生成と `MeshDef` テンプレートからの頂点展開。

use crate::MeshVertex;
use std::collections::HashMap;

/// 軸平行ボックスの頂点（8 個）・インデックス（36 個）を生成する。
pub(super) fn box_mesh(
    cx: f32,
    cy: f32,
    cz: f32,
    hw: f32,
    hh: f32,
    hd: f32,
    color: [f32; 4],
) -> ([MeshVertex; 8], [u32; 36]) {
    let (x0, x1) = (cx - hw, cx + hw);
    let (y0, y1) = (cy - hh, cy + hh);
    let (z0, z1) = (cz - hd, cz + hd);

    let v = |pos| MeshVertex {
        position: pos,
        color,
    };
    let verts = [
        v([x0, y0, z0]),
        v([x1, y0, z0]),
        v([x1, y1, z0]),
        v([x0, y1, z0]),
        v([x0, y0, z1]),
        v([x1, y0, z1]),
        v([x1, y1, z1]),
        v([x0, y1, z1]),
    ];

    #[rustfmt::skip]
    let idx: [u32; 36] = [
        0,1,2, 0,2,3, // -Z 面
        5,4,7, 5,7,6, // +Z 面
        4,0,3, 4,3,7, // -X 面
        1,5,6, 1,6,2, // +X 面
        3,2,6, 3,6,7, // +Y 面
        4,5,1, 4,1,0, // -Y 面
    ];

    (verts, idx)
}

/// `MeshDef` テンプレート（`unit_box` / `unit_sphere` / `unit_cone` 等）を half 拡張でスケールしスクラッチに追加する。
///
/// キャッシュ未登録または空インデックス時は [`box_mesh`] にフォールバックする。
/// `unit_box` 以外ではシルエットが一致しないため、その場合は [`log::warn`] する（`unit_box` 欠落時は同形状のためログしない）。
pub(super) fn push_mesh_from_def(
    cache: &HashMap<String, (Vec<MeshVertex>, Vec<u32>)>,
    mesh_name: &str,
    x: f32,
    y: f32,
    z: f32,
    half_w: f32,
    half_h: f32,
    half_d: f32,
    color: [f32; 4],
    verts_out: &mut Vec<MeshVertex>,
    indices_out: &mut Vec<u32>,
) {
    let base = verts_out.len() as u32;
    if let Some((template, indices)) = cache.get(mesh_name) {
        if !indices.is_empty() {
            let hw = half_w * 2.0;
            let hh = half_h * 2.0;
            let hd = half_d * 2.0;
            verts_out.extend(template.iter().map(|v| MeshVertex {
                position: [
                    v.position[0] * hw + x,
                    v.position[1] * hh + y,
                    v.position[2] * hd + z,
                ],
                color,
            }));
            indices_out.extend(indices.iter().map(|&i| i + base));
            return;
        }
        log::warn!(
            "pipeline_3d: MeshDef {:?} is cached but has empty indices; using procedural box fallback",
            mesh_name
        );
    } else if mesh_name != "unit_box" {
        log::warn!(
            "pipeline_3d: MeshDef {:?} missing from frame mesh_definitions; using procedural box (incorrect for sphere/cone)",
            mesh_name
        );
    }

    let (v, i) = box_mesh(x, y, z, half_w, half_h, half_d, color);
    verts_out.extend(v);
    indices_out.extend(i.iter().map(|&idx| idx + base));
}

/// XZ 平面上のグリッドラインを生成する（ラインリスト用）。
pub(super) fn grid_lines(size: f32, divisions: u32, color: [f32; 4], out: &mut Vec<MeshVertex>) {
    let half = size / 2.0;
    let step = size / divisions as f32;
    let n = divisions + 1;
    for i in 0..n {
        let t = -half + i as f32 * step;
        out.push(MeshVertex {
            position: [-half, 0.0, t],
            color,
        });
        out.push(MeshVertex {
            position: [half, 0.0, t],
            color,
        });
        out.push(MeshVertex {
            position: [t, 0.0, -half],
            color,
        });
        out.push(MeshVertex {
            position: [t, 0.0, half],
            color,
        });
    }
}

/// スカイボックス用グラデーション矩形の頂点（4 個）を生成する。
pub(super) fn skybox_verts(top: [f32; 4], bottom: [f32; 4]) -> [MeshVertex; 4] {
    [
        MeshVertex {
            position: [-1.0, 1.0, 0.999],
            color: top,
        },
        MeshVertex {
            position: [1.0, 1.0, 0.999],
            color: top,
        },
        MeshVertex {
            position: [1.0, -1.0, 0.999],
            color: bottom,
        },
        MeshVertex {
            position: [-1.0, -1.0, 0.999],
            color: bottom,
        },
    ]
}

pub(super) const SKYBOX_INDICES: [u32; 6] = [0, 1, 2, 0, 2, 3];
