//! 3D レンダリングパイプライン（Phase R-5）
//!
//! `DrawCommand::Box3D` / `GridPlane` / `Skybox` を wgpu で描画する。
//! 描画順: スカイボックス（深度テストなし）→ グリッド → ボックス（深度テストあり）。
//!
//! ## バッファ設計
//! GPU バッファは `new()` 時に最大容量で事前確保し、毎フレームは `write_buffer` で
//! 内容を上書きする。フレームごとの `create_buffer` 呼び出しは行わない。
//!
//! ## Uniform バッファ設計
//! スカイボックスは MVP 変換を通さずクリップ座標を直接渡す（`vs_sky` エントリポイント）。
//! メッシュ・グリッドは `vs_main` を使い、`mvp_buf` に書き込んだカメラ行列を適用する。
//! 2 つのパスで同じ `mvp_buf` を共有しても問題ない。スカイボックスは MVP を参照しない
//! シェーダーエントリポイントを使うため、`mvp_buf` の内容に依存しない。

use crate::DrawCommand;
use crate::{MeshDef, MeshVertex};
use std::collections::HashMap;
use wgpu::util::DeviceExt;

// ─── 容量定数 ─────────────────────────────────────────────────────────────

/// グリッドライン頂点の最大数。
/// divisions=100 の場合: (100 + 1) 本 × 2 方向 × 2 頂点 = 404 頂点。
const MAX_GRID_VERTS: usize = 404;

/// ボックス頂点の最大数（8 頂点 × 最大 256 ボックス）。
const MAX_BOX_VERTS: usize = 8 * 256;

/// ボックスインデックスの最大数（36 インデックス × 最大 256 ボックス）。
const MAX_BOX_INDICES: usize = 36 * 256;

/// スカイボックス頂点数（固定: 4 頂点 2 三角形）。
const SKYBOX_VERT_COUNT: usize = 4;

// ─── MVP Uniform ─────────────────────────────────────────────────────────

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct MvpUniform {
    mvp: [[f32; 4]; 4],
}

impl MvpUniform {
    fn identity() -> Self {
        Self {
            mvp: [
                [1.0, 0.0, 0.0, 0.0],
                [0.0, 1.0, 0.0, 0.0],
                [0.0, 0.0, 1.0, 0.0],
                [0.0, 0.0, 0.0, 1.0],
            ],
        }
    }

    /// ビュー行列・透視投影行列を合成した VP 行列を構築する（行列は列優先）。
    fn from_camera(
        eye: [f32; 3],
        target: [f32; 3],
        up: [f32; 3],
        fov_deg: f32,
        aspect: f32,
        near: f32,
        far: f32,
    ) -> Self {
        let view = look_at(eye, target, up);
        let proj = perspective(fov_deg.to_radians(), aspect, near, far);
        Self {
            mvp: mat4_mul(proj, view),
        }
    }
}

// ─── 行列演算ヘルパー ─────────────────────────────────────────────────────

fn look_at(eye: [f32; 3], center: [f32; 3], up: [f32; 3]) -> [[f32; 4]; 4] {
    let f = normalize(sub3(center, eye));
    let r = normalize(cross3(f, up));
    let u = cross3(r, f);
    [
        [r[0], u[0], -f[0], 0.0],
        [r[1], u[1], -f[1], 0.0],
        [r[2], u[2], -f[2], 0.0],
        [-dot3(r, eye), -dot3(u, eye), dot3(f, eye), 1.0],
    ]
}

fn perspective(fov_rad: f32, aspect: f32, near: f32, far: f32) -> [[f32; 4]; 4] {
    let tan_half = (fov_rad / 2.0).tan();
    let range = far - near;
    [
        [1.0 / (aspect * tan_half), 0.0, 0.0, 0.0],
        [0.0, 1.0 / tan_half, 0.0, 0.0],
        [0.0, 0.0, -(far + near) / range, -1.0],
        [0.0, 0.0, -2.0 * far * near / range, 0.0],
    ]
}

fn mat4_mul(a: [[f32; 4]; 4], b: [[f32; 4]; 4]) -> [[f32; 4]; 4] {
    let mut out = [[0.0f32; 4]; 4];
    for col in 0..4 {
        for row in 0..4 {
            out[col][row] = (0..4).map(|k| a[k][row] * b[col][k]).sum();
        }
    }
    out
}

fn sub3(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn dot3(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn cross3(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}
fn normalize(v: [f32; 3]) -> [f32; 3] {
    let len = dot3(v, v).sqrt().max(f32::EPSILON);
    [v[0] / len, v[1] / len, v[2] / len]
}

// ─── メッシュ生成ヘルパー ─────────────────────────────────────────────────

/// 軸平行ボックスの頂点（8 個）・インデックス（36 個）を生成する。
fn box_mesh(
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

/// XZ 平面上のグリッドラインを生成する（ラインリスト用）。
fn grid_lines(size: f32, divisions: u32, color: [f32; 4], out: &mut Vec<MeshVertex>) {
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
///
/// クリップ空間を直接指定する（`vs_sky` エントリポイントは MVP 変換を行わない）。
/// depth = 0.999 とすることで深度テストなしパスで最背面に描画される。
fn skybox_verts(top: [f32; 4], bottom: [f32; 4]) -> [MeshVertex; 4] {
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

const SKYBOX_INDICES: [u32; 6] = [0, 1, 2, 0, 2, 3];

// ─── DepthStencilState ヘルパー ───────────────────────────────────────────

fn depth_stencil_write() -> wgpu::DepthStencilState {
    wgpu::DepthStencilState {
        format: wgpu::TextureFormat::Depth32Float,
        depth_write_enabled: true,
        depth_compare: wgpu::CompareFunction::Less,
        stencil: wgpu::StencilState::default(),
        bias: wgpu::DepthBiasState::default(),
    }
}

// ─── Pipeline3D ──────────────────────────────────────────────────────────

/// 3D レンダリングに必要な wgpu リソースをまとめた構造体。
pub(crate) struct Pipeline3D {
    device: std::sync::Arc<wgpu::Device>,
    queue: std::sync::Arc<wgpu::Queue>,
    /// メッシュ（ボックス）用パイプライン（三角形リスト、深度テストあり）
    mesh_pipeline: wgpu::RenderPipeline,
    /// グリッドライン用パイプライン（ラインリスト、深度テストあり）
    grid_pipeline: wgpu::RenderPipeline,
    /// スカイボックス用パイプライン（深度テストなし、`vs_sky` エントリポイント使用）
    sky_pipeline: wgpu::RenderPipeline,
    /// 3D カメラ VP 行列 Uniform バッファ（メッシュ・グリッドパスで使用）
    mvp_buf: wgpu::Buffer,
    mvp_bind_group: wgpu::BindGroup,
    /// 深度テクスチャ（リサイズ時に再生成）
    depth_texture: wgpu::Texture,
    depth_view: wgpu::TextureView,
    /// 事前確保済みグリッド頂点バッファ（COPY_DST | VERTEX）
    grid_vbuf: wgpu::Buffer,
    /// 事前確保済みボックス頂点バッファ（COPY_DST | VERTEX）
    box_vbuf: wgpu::Buffer,
    /// 事前確保済みボックスインデックスバッファ（COPY_DST | INDEX）
    box_ibuf: wgpu::Buffer,
    /// 事前確保済みスカイボックス頂点バッファ（COPY_DST | VERTEX）
    sky_vbuf: wgpu::Buffer,
    /// スカイボックスインデックスバッファ（固定内容、初期化時に一度だけ書き込む）
    sky_ibuf: wgpu::Buffer,
    width: u32,
    height: u32,
    /// CPU スクラッチバッファ（毎フレーム clear() して再利用し、ヒープ再確保を避ける）
    grid_verts_scratch: Vec<MeshVertex>,
    box_verts_scratch: Vec<MeshVertex>,
    box_indices_scratch: Vec<u32>,
    /// P3: Elixir 定義のメッシュキャッシュ（unit_box, skybox_quad 等）
    mesh_def_cache: HashMap<String, (Vec<MeshVertex>, Vec<u32>)>,
    /// 直前フレームで登録した mesh_definitions の名前リスト。同じなら insert をスキップする。
    mesh_def_cache_key: Option<Vec<String>>,
}

impl Pipeline3D {
    /// P4: mesh_wgsl が Some の場合はコンテンツ定義の WGSL を使用。
    /// None の場合は include_str! フォールバック。
    pub(crate) fn new(
        device: std::sync::Arc<wgpu::Device>,
        queue: std::sync::Arc<wgpu::Queue>,
        surface_format: wgpu::TextureFormat,
        width: u32,
        height: u32,
        mesh_wgsl: Option<&str>,
    ) -> Self {
        let shader_source =
            mesh_wgsl.unwrap_or_else(|| include_str!("shaders/mesh.wgsl"));
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Mesh Shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        // ─── MVP Uniform バインドグループ ─────────────────────────
        let mvp_bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("MVP BGL"),
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::VERTEX,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });

        let mvp_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("MVP Uniform Buffer"),
            contents: bytemuck::bytes_of(&MvpUniform::identity()),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let mvp_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("MVP Bind Group"),
            layout: &mvp_bgl,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: mvp_buf.as_entire_binding(),
            }],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Mesh Pipeline Layout"),
            bind_group_layouts: &[&mvp_bgl],
            push_constant_ranges: &[],
        });

        let vertex_buffers = &[wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<MeshVertex>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &wgpu::vertex_attr_array![
                0 => Float32x3, // position
                1 => Float32x4, // color
            ],
        }];

        // ─── メッシュパイプライン（三角形リスト、深度テストあり）───
        let mesh_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Mesh Pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: vertex_buffers,
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: surface_format,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                cull_mode: Some(wgpu::Face::Back),
                ..Default::default()
            },
            depth_stencil: Some(depth_stencil_write()),
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });

        // ─── グリッドパイプライン（ラインリスト、深度テストあり）───
        let grid_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Grid Pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: vertex_buffers,
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: surface_format,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::LineList,
                ..Default::default()
            },
            depth_stencil: Some(depth_stencil_write()),
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });

        // ─── スカイボックスパイプライン（深度テストなし）────────────
        // `vs_sky` エントリポイントは MVP 変換を行わず、頂点座標をクリップ空間として
        // そのまま出力する。`mvp_buf` の内容には依存しない。
        let sky_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Skybox Pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_sky"),
                buffers: vertex_buffers,
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: surface_format,
                    blend: None,
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                cull_mode: None,
                ..Default::default()
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });

        let (depth_texture, depth_view) = create_depth_texture(&device, width, height);

        // ─── 事前確保バッファ ─────────────────────────────────────
        let grid_vbuf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Grid VBuf"),
            size: (std::mem::size_of::<MeshVertex>() * MAX_GRID_VERTS) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let box_vbuf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Box VBuf"),
            size: (std::mem::size_of::<MeshVertex>() * MAX_BOX_VERTS) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let box_ibuf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Box IBuf"),
            size: (std::mem::size_of::<u32>() * MAX_BOX_INDICES) as u64,
            usage: wgpu::BufferUsages::INDEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let sky_vbuf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Skybox VBuf"),
            size: (std::mem::size_of::<MeshVertex>() * SKYBOX_VERT_COUNT) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // スカイボックスインデックスは固定値のため初期化時に一度だけ書き込む
        let sky_ibuf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Skybox IBuf"),
            contents: bytemuck::cast_slice(&SKYBOX_INDICES),
            usage: wgpu::BufferUsages::INDEX,
        });

        Self {
            device,
            queue,
            mesh_pipeline,
            grid_pipeline,
            sky_pipeline,
            mvp_buf,
            mvp_bind_group,
            depth_texture,
            depth_view,
            grid_vbuf,
            box_vbuf,
            box_ibuf,
            sky_vbuf,
            sky_ibuf,
            width,
            height,
            grid_verts_scratch: Vec::with_capacity(MAX_GRID_VERTS),
            box_verts_scratch: Vec::with_capacity(MAX_BOX_VERTS),
            box_indices_scratch: Vec::with_capacity(MAX_BOX_INDICES),
            mesh_def_cache: HashMap::new(),
            mesh_def_cache_key: None,
        }
    }

    /// ウィンドウリサイズ時に深度テクスチャを再生成する。
    pub(crate) fn resize(&mut self, width: u32, height: u32) {
        self.width = width;
        self.height = height;
        let (tex, view) = create_depth_texture(&self.device, width, height);
        self.depth_texture = tex;
        self.depth_view = view;
    }

    /// `DrawCommand` リストを 3D パスで描画する。
    ///
    /// `camera` が `Camera3D` 以外の場合は即座にリターンする。
    /// 描画順: スカイボックス（深度テストなし）→ グリッド + ボックス（深度テストあり）。
    /// P3: mesh_definitions が非空の場合、キャッシュに登録し、unit_box / skybox_quad を
    /// 使用する。未登録時は従来の box_mesh / skybox_verts にフォールバック。
    pub(crate) fn render(
        &mut self,
        encoder: &mut wgpu::CommandEncoder,
        color_view: &wgpu::TextureView,
        commands: &[DrawCommand],
        camera: &crate::CameraParams,
        mesh_definitions: &[MeshDef],
    ) {
        let crate::CameraParams::Camera3D {
            eye,
            target,
            up,
            fov_deg,
            near,
            far,
        } = camera
        else {
            return;
        };

        // ─── P3: メッシュ定義をキャッシュに登録（直前フレームと同じ場合はスキップ）────
        let new_key: Vec<String> = mesh_definitions.iter().map(|d| d.name.clone()).collect();
        if self.mesh_def_cache_key.as_ref() != Some(&new_key) {
            for def in mesh_definitions {
                self.mesh_def_cache.insert(
                    def.name.clone(),
                    (def.vertices.clone(), def.indices.clone()),
                );
            }
            self.mesh_def_cache_key = Some(new_key);
        }

        // ─── MVP Uniform を 3D カメラ行列で更新 ──────────────────
        let aspect = self.width as f32 / self.height as f32;
        let mvp = MvpUniform::from_camera(*eye, *target, *up, *fov_deg, aspect, *near, *far);
        self.queue
            .write_buffer(&self.mvp_buf, 0, bytemuck::bytes_of(&mvp));

        // ─── スカイボックスパス ───────────────────────────────────
        // `sky_pipeline` は `vs_sky` エントリポイントを使用するため、
        // `mvp_buf` の内容（3D カメラ行列）に依存しない。
        // 別 Uniform バッファは不要。
        let sky_cmd = commands.iter().find_map(|c| {
            if let DrawCommand::Skybox {
                top_color,
                bottom_color,
            } = c
            {
                Some((*top_color, *bottom_color))
            } else {
                None
            }
        });

        if let Some((top, bottom)) = sky_cmd {
            let verts: Vec<MeshVertex> = if let Some((template, _)) =
                self.mesh_def_cache.get("skybox_quad")
            {
                // P3: Elixir 定義の skybox_quad を使用し、色を top/bottom で上書き
                template
                    .iter()
                    .enumerate()
                    .map(|(i, v)| {
                        let color = if i < 2 { top } else { bottom };
                        MeshVertex {
                            position: v.position,
                            color,
                        }
                    })
                    .collect()
            } else {
                skybox_verts(top, bottom).to_vec()
            };
            self.queue
                .write_buffer(&self.sky_vbuf, 0, bytemuck::cast_slice(&verts));

            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Skybox Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: color_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Load,
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(&self.sky_pipeline);
            // `vs_sky` は u_mvp を参照しないが、パイプラインレイアウトの互換性維持のため設定する
            pass.set_bind_group(0, &self.mvp_bind_group, &[]);
            pass.set_vertex_buffer(0, self.sky_vbuf.slice(..));
            pass.set_index_buffer(self.sky_ibuf.slice(..), wgpu::IndexFormat::Uint32);
            pass.draw_indexed(0..SKYBOX_INDICES.len() as u32, 0, 0..1);
        }

        // ─── グリッド + ボックスパス（深度テストあり）──────────────
        // スクラッチバッファを clear() して再利用し、毎フレームのヒープ確保を避ける
        self.grid_verts_scratch.clear();
        self.box_verts_scratch.clear();
        self.box_indices_scratch.clear();

        for cmd in commands {
            match cmd {
                DrawCommand::GridPlaneVerts { vertices } => {
                    self.grid_verts_scratch.extend(vertices);
                }
                DrawCommand::GridPlane {
                    size,
                    divisions,
                    color,
                } => {
                    grid_lines(*size, *divisions, *color, &mut self.grid_verts_scratch);
                }
                DrawCommand::Box3D {
                    x,
                    y,
                    z,
                    half_w,
                    half_h,
                    half_d,
                    color,
                } => {
                    let base = self.box_verts_scratch.len() as u32;
                    let (verts, idx) = if let Some((template, indices)) =
                        self.mesh_def_cache.get("unit_box")
                    {
                        // P3: Elixir 定義の unit_box を使用。スケール・移動・色を適用
                        let hw = *half_w * 2.0;
                        let hh = *half_h * 2.0;
                        let hd = *half_d * 2.0;
                        let verts: Vec<MeshVertex> = template
                            .iter()
                            .map(|v| MeshVertex {
                                position: [
                                    v.position[0] * hw + x,
                                    v.position[1] * hh + y,
                                    v.position[2] * hd + z,
                                ],
                                color: *color,
                            })
                            .collect();
                        let idx: Vec<u32> =
                            indices.iter().map(|&i| i + base).collect();
                        (verts, idx)
                    } else {
                        let (v, i) = box_mesh(*x, *y, *z, *half_w, *half_h, *half_d, *color);
                        (
                            v.to_vec(),
                            i.iter().map(|&i| i + base).collect::<Vec<_>>(),
                        )
                    };
                    self.box_verts_scratch.extend(verts);
                    self.box_indices_scratch.extend(idx);
                }
                _ => {}
            }
        }

        // スカイボックスのみ描画済みの場合もここで抜ける
        if self.grid_verts_scratch.is_empty() && self.box_verts_scratch.is_empty() {
            return;
        }

        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("3D Pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: color_view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Load,
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                view: &self.depth_view,
                depth_ops: Some(wgpu::Operations {
                    load: wgpu::LoadOp::Clear(1.0),
                    store: wgpu::StoreOp::Store,
                }),
                stencil_ops: None,
            }),
            timestamp_writes: None,
            occlusion_query_set: None,
        });

        pass.set_bind_group(0, &self.mvp_bind_group, &[]);

        if !self.grid_verts_scratch.is_empty() {
            debug_assert!(
                self.grid_verts_scratch.len() <= MAX_GRID_VERTS,
                "grid_verts が上限 {} を超えています（{}）。MAX_GRID_VERTS を増やしてください。",
                MAX_GRID_VERTS,
                self.grid_verts_scratch.len()
            );
            let count = self.grid_verts_scratch.len().min(MAX_GRID_VERTS);
            let byte_len = (count * std::mem::size_of::<MeshVertex>()) as u64;
            self.queue.write_buffer(
                &self.grid_vbuf,
                0,
                bytemuck::cast_slice(&self.grid_verts_scratch[..count]),
            );
            pass.set_pipeline(&self.grid_pipeline);
            pass.set_vertex_buffer(0, self.grid_vbuf.slice(..byte_len));
            pass.draw(0..count as u32, 0..1);
        }

        if !self.box_verts_scratch.is_empty() {
            debug_assert!(
                self.box_verts_scratch.len() <= MAX_BOX_VERTS,
                "box_verts が上限 {} を超えています（{}）。MAX_BOX_VERTS を増やしてください。",
                MAX_BOX_VERTS,
                self.box_verts_scratch.len()
            );
            debug_assert!(
                self.box_indices_scratch.len() <= MAX_BOX_INDICES,
                "box_indices が上限 {} を超えています（{}）。MAX_BOX_INDICES を増やしてください。",
                MAX_BOX_INDICES,
                self.box_indices_scratch.len()
            );
            let vcount = self.box_verts_scratch.len().min(MAX_BOX_VERTS);
            let icount = self.box_indices_scratch.len().min(MAX_BOX_INDICES);
            let vbyte_len = (vcount * std::mem::size_of::<MeshVertex>()) as u64;
            let ibyte_len = (icount * std::mem::size_of::<u32>()) as u64;
            self.queue.write_buffer(
                &self.box_vbuf,
                0,
                bytemuck::cast_slice(&self.box_verts_scratch[..vcount]),
            );
            self.queue.write_buffer(
                &self.box_ibuf,
                0,
                bytemuck::cast_slice(&self.box_indices_scratch[..icount]),
            );
            pass.set_pipeline(&self.mesh_pipeline);
            pass.set_vertex_buffer(0, self.box_vbuf.slice(..vbyte_len));
            pass.set_index_buffer(self.box_ibuf.slice(..ibyte_len), wgpu::IndexFormat::Uint32);
            pass.draw_indexed(0..icount as u32, 0, 0..1);
        }
    }
}

fn create_depth_texture(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> (wgpu::Texture, wgpu::TextureView) {
    let tex = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("Depth Texture"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Depth32Float,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
        view_formats: &[],
    });
    let view = tex.create_view(&Default::default());
    (tex, view)
}
