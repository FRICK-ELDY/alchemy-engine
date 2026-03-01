//! Path: native/game_render/src/headless.rs
//! Summary: ヘッドレス/オフスクリーンレンダリングモード（`headless` フィーチャー有効時のみ利用可能）
//!
//! ウィンドウを開かずに wgpu のオフスクリーンターゲットへ描画し、
//! PNG バイト列を返す。CI でのレンダリング回帰テストに使用する。

use crate::{
    renderer::{
        bullet_uv, enemy_anim_uv, enemy_sprite_size, fireball_uv, gem_uv,
        lightning_bullet_uv, magnet_uv, particle_uv, player_anim_uv, potion_uv,
        rock_bullet_uv, whip_uv, SpriteInstance, ELITE_RENDER_KIND_OFFSET,
        ELITE_SIZE_MULTIPLIER, MAX_INSTANCES,
    },
    RenderFrame,
};
use game_physics::constants::{BG_B, BG_G, BG_R, SPRITE_SIZE};
use game_physics::item::{RENDER_KIND_GEM, RENDER_KIND_MAGNET, RENDER_KIND_POTION};
use image::{ImageBuffer, Rgba};
use wgpu::util::DeviceExt;

const DEFAULT_WIDTH: u32 = 800;
const DEFAULT_HEIGHT: u32 = 600;

/// wgpu デバイス・キューを保持するオフスクリーンレンダラー。
///
/// ウィンドウ・サーフェスを持たず、テクスチャターゲットに直接描画する。
/// `render_frame_offscreen` を複数回呼び出す場合、レンダーターゲットと
/// 読み出しバッファは呼び出しごとに再生成される。CI での単発スクリーンショット
/// 取得を主用途とするため、この設計で十分と判断している。
/// 連続フレームのベンチマーク用途では `target_texture` / `readback_buffer` を
/// フィールドに持たせてキャッシュすることを検討すること。
pub struct HeadlessRenderer {
    device: wgpu::Device,
    queue: wgpu::Queue,
    render_pipeline: wgpu::RenderPipeline,
    vertex_buffer: wgpu::Buffer,
    index_buffer: wgpu::Buffer,
    instance_buffer: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    /// 画面サイズ Uniform バッファ（GPU バインドグループ経由で参照されるため保持）
    _screen_uniform_buf: wgpu::Buffer,
    screen_bind_group: wgpu::BindGroup,
    camera_uniform_buf: wgpu::Buffer,
    camera_bind_group: wgpu::BindGroup,
    width: u32,
    height: u32,
    texture_format: wgpu::TextureFormat,
}

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct Vertex {
    position: [f32; 2],
}

const VERTICES: &[Vertex] = &[
    Vertex {
        position: [0.0, 0.0],
    },
    Vertex {
        position: [1.0, 0.0],
    },
    Vertex {
        position: [1.0, 1.0],
    },
    Vertex {
        position: [0.0, 1.0],
    },
];

const INDICES: &[u16] = &[0, 1, 2, 0, 2, 3];

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct ScreenUniform {
    half_size: [f32; 2],
    _pad: [f32; 2],
}

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct CameraUniform {
    offset: [f32; 2],
    _pad: [f32; 2],
}

impl HeadlessRenderer {
    /// ヘッドレスレンダラーを初期化する。
    ///
    /// # 引数
    /// - `atlas_bytes`: スプライトアトラス PNG のバイト列
    /// - `width` / `height`: 出力画像のピクセルサイズ（`None` の場合は 800×600）
    ///
    /// # エラー
    /// wgpu アダプター・デバイスの取得失敗やアトラス画像のデコード失敗時に
    /// エラー文字列を返す。
    pub fn new(
        atlas_bytes: &[u8],
        width: Option<u32>,
        height: Option<u32>,
    ) -> Result<Self, String> {
        pollster::block_on(Self::new_async(atlas_bytes, width, height))
    }

    async fn new_async(
        atlas_bytes: &[u8],
        width: Option<u32>,
        height: Option<u32>,
    ) -> Result<Self, String> {
        let width = width.unwrap_or(DEFAULT_WIDTH);
        let height = height.unwrap_or(DEFAULT_HEIGHT);

        let instance = wgpu::Instance::default();

        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::None,
                compatible_surface: None,
                force_fallback_adapter: false,
            })
            .await
            .ok_or_else(|| "ヘッドレスアダプターの取得に失敗しました".to_string())?;

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor::default(), None)
            .await
            .map_err(|e| format!("ヘッドレスデバイスの取得に失敗しました: {e}"))?;

        // Rgba8Unorm はオフスクリーン用途で最も互換性が高い
        let texture_format = wgpu::TextureFormat::Rgba8Unorm;

        // ─── テクスチャアトラス ───────────────────────────────────
        let atlas_image = image::load_from_memory(atlas_bytes)
            .map_err(|e| format!("atlas.png の読み込みに失敗しました: {e}"))?
            .to_rgba8();
        let atlas_size = wgpu::Extent3d {
            width: atlas_image.width(),
            height: atlas_image.height(),
            depth_or_array_layers: 1,
        };
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Headless Atlas Texture"),
            size: atlas_size,
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8UnormSrgb,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            &atlas_image,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(4 * atlas_image.width()),
                rows_per_image: Some(atlas_image.height()),
            },
            atlas_size,
        );
        let texture_view = texture.create_view(&Default::default());
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Headless Atlas Sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Nearest,
            min_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        // ─── バインドグループ group(0): テクスチャ ───────────────
        let texture_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Headless Texture BGL"),
                entries: &[
                    wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Texture {
                            multisampled: false,
                            view_dimension: wgpu::TextureViewDimension::D2,
                            sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        },
                        count: None,
                    },
                    wgpu::BindGroupLayoutEntry {
                        binding: 1,
                        visibility: wgpu::ShaderStages::FRAGMENT,
                        ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                        count: None,
                    },
                ],
            });
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Headless Texture BG"),
            layout: &texture_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&texture_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
            ],
        });

        // ─── バインドグループ group(1): 画面サイズ Uniform ─────
        let screen_uniform = ScreenUniform {
            half_size: [width as f32 / 2.0, height as f32 / 2.0],
            _pad: [0.0; 2],
        };
        let screen_uniform_buf =
            device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Headless Screen Uniform"),
                contents: bytemuck::bytes_of(&screen_uniform),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });
        let screen_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Headless Screen BGL"),
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
        let screen_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Headless Screen BG"),
            layout: &screen_bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: screen_uniform_buf.as_entire_binding(),
            }],
        });

        // ─── バインドグループ group(2): カメラ Uniform ──────────
        let camera_uniform = CameraUniform {
            offset: [0.0, 0.0],
            _pad: [0.0; 2],
        };
        let camera_uniform_buf =
            device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("Headless Camera Uniform"),
                contents: bytemuck::bytes_of(&camera_uniform),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });
        let camera_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Headless Camera BGL"),
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
        let camera_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Headless Camera BG"),
            layout: &camera_bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: camera_uniform_buf.as_entire_binding(),
            }],
        });

        // ─── シェーダー・パイプライン ─────────────────────────────
        let shader_source = include_str!("renderer/shaders/sprite.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Headless Sprite Shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        let pipeline_layout =
            device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Headless Pipeline Layout"),
                bind_group_layouts: &[
                    &texture_bind_group_layout,
                    &screen_bind_group_layout,
                    &camera_bind_group_layout,
                ],
                push_constant_ranges: &[],
            });

        let render_pipeline =
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("Headless Sprite Pipeline"),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &shader,
                    entry_point: Some("vs_main"),
                    buffers: &[
                        wgpu::VertexBufferLayout {
                            array_stride: std::mem::size_of::<Vertex>() as wgpu::BufferAddress,
                            step_mode: wgpu::VertexStepMode::Vertex,
                            attributes: &wgpu::vertex_attr_array![0 => Float32x2],
                        },
                        wgpu::VertexBufferLayout {
                            array_stride: std::mem::size_of::<SpriteInstance>()
                                as wgpu::BufferAddress,
                            step_mode: wgpu::VertexStepMode::Instance,
                            attributes: &wgpu::vertex_attr_array![
                                1 => Float32x2,
                                2 => Float32x2,
                                3 => Float32x2,
                                4 => Float32x2,
                                5 => Float32x4,
                            ],
                        },
                    ],
                    compilation_options: Default::default(),
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader,
                    entry_point: Some("fs_main"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format: texture_format,
                        blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                primitive: wgpu::PrimitiveState {
                    topology: wgpu::PrimitiveTopology::TriangleList,
                    strip_index_format: None,
                    front_face: wgpu::FrontFace::Ccw,
                    cull_mode: None,
                    ..Default::default()
                },
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                multiview: None,
                cache: None,
            });

        // ─── 頂点・インデックス・インスタンスバッファ ───────────
        let vertex_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Headless Vertex Buffer"),
            contents: bytemuck::cast_slice(VERTICES),
            usage: wgpu::BufferUsages::VERTEX,
        });
        let index_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Headless Index Buffer"),
            contents: bytemuck::cast_slice(INDICES),
            usage: wgpu::BufferUsages::INDEX,
        });
        let instance_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Headless Instance Buffer"),
            size: (std::mem::size_of::<SpriteInstance>() * MAX_INSTANCES) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        Ok(Self {
            device,
            queue,
            render_pipeline,
            vertex_buffer,
            index_buffer,
            instance_buffer,
            bind_group,
            _screen_uniform_buf: screen_uniform_buf,
            screen_bind_group,
            camera_uniform_buf,
            camera_bind_group,
            width,
            height,
            texture_format,
        })
    }

    /// `RenderFrame` をオフスクリーンターゲットに描画し、PNG バイト列を返す。
    ///
    /// CI でのスクリーンショット比較テストや回帰テストに使用する。
    ///
    /// # エラー
    /// GPU バッファのマップ失敗や PNG エンコード失敗時にエラー文字列を返す。
    pub fn render_frame_offscreen(&mut self, frame: &RenderFrame) -> Result<Vec<u8>, String> {
        // カメラ Uniform を更新
        let cam_uniform = CameraUniform {
            offset: [frame.camera_offset.0, frame.camera_offset.1],
            _pad: [0.0; 2],
        };
        self.queue
            .write_buffer(&self.camera_uniform_buf, 0, bytemuck::bytes_of(&cam_uniform));

        // インスタンスリストを構築（通常レンダラーと共有の関数を使用）
        let instances = build_instances(frame);
        let instance_count = instances.len() as u32;
        if !instances.is_empty() {
            self.queue.write_buffer(
                &self.instance_buffer,
                0,
                bytemuck::cast_slice(&instances),
            );
        }

        // オフスクリーン描画ターゲットを生成
        let target_texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Headless Render Target"),
            size: wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: self.texture_format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let target_view = target_texture.create_view(&Default::default());

        // ピクセル読み出し用バッファ（wgpu の COPY_BYTES_PER_ROW_ALIGNMENT に合わせる）
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
        let bytes_per_pixel = 4u32;
        let unpadded_bytes_per_row = self.width * bytes_per_pixel;
        let padded_bytes_per_row = (unpadded_bytes_per_row + align - 1) / align * align;

        let readback_buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Headless Readback Buffer"),
            size: (padded_bytes_per_row * self.height) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        // コマンドエンコード
        let mut encoder =
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("Headless Encoder"),
                });

        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Headless Sprite Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &target_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: BG_R,
                            g: BG_G,
                            b: BG_B,
                            a: 1.0,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });

            if instance_count > 0 {
                pass.set_pipeline(&self.render_pipeline);
                pass.set_bind_group(0, &self.bind_group, &[]);
                pass.set_bind_group(1, &self.screen_bind_group, &[]);
                pass.set_bind_group(2, &self.camera_bind_group, &[]);
                pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
                pass.set_vertex_buffer(1, self.instance_buffer.slice(..));
                pass.set_index_buffer(self.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
                pass.draw_indexed(0..INDICES.len() as u32, 0, 0..instance_count);
            }
        }

        // テクスチャ → 読み出しバッファへコピー
        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo {
                texture: &target_texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::TexelCopyBufferInfo {
                buffer: &readback_buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(padded_bytes_per_row),
                    rows_per_image: Some(self.height),
                },
            },
            wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: 1,
            },
        );

        // submit してインデックスを取得し、そのサブミッションの完了まで待機する
        let submission_index = self.queue.submit([encoder.finish()]);

        // map_async を先に登録してからポーリングする。
        // wgpu の仕様上、map_async のコールバックは poll() 呼び出し中に
        // 同期的に実行されるため、WaitForSubmissionIndex が返った時点で
        // rx には必ず値が入っている。rx.recv() の RecvError パスは
        // 理論上到達しないが、API 契約の変化に備えて防御的に残している。
        let buffer_slice = readback_buffer.slice(..);
        let (tx, rx) = std::sync::mpsc::channel();
        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = tx.send(result);
        });
        self.device
            .poll(wgpu::Maintain::WaitForSubmissionIndex(submission_index));
        rx.recv()
            .map_err(|_| "マップ完了チャンネルの受信に失敗しました".to_string())?
            .map_err(|e| format!("GPU バッファのマップに失敗しました: {e:?}"))?;

        // パディングを除去して RGBA ピクセル列を構築
        let mapped = buffer_slice.get_mapped_range();
        let mut pixels: Vec<u8> =
            Vec::with_capacity((self.width * self.height * 4) as usize);
        for row in 0..self.height as usize {
            let start = row * padded_bytes_per_row as usize;
            let end = start + unpadded_bytes_per_row as usize;
            pixels.extend_from_slice(&mapped[start..end]);
        }
        drop(mapped);
        readback_buffer.unmap();

        // PNG エンコード
        let img: ImageBuffer<Rgba<u8>, Vec<u8>> =
            ImageBuffer::from_raw(self.width, self.height, pixels)
                .ok_or_else(|| "ImageBuffer の構築に失敗しました".to_string())?;
        let mut png_bytes: Vec<u8> = Vec::new();
        img.write_to(
            &mut std::io::Cursor::new(&mut png_bytes),
            image::ImageFormat::Png,
        )
        .map_err(|e| format!("PNG エンコードに失敗しました: {e}"))?;

        Ok(png_bytes)
    }
}

/// `RenderFrame` からスプライトインスタンスリストを構築する。
///
/// スプライト種別ごとの UV・サイズ計算は通常レンダラー（`renderer/mod.rs`）と
/// 共有の `pub(crate)` 関数を使用しており、二重管理を排除している。
fn build_instances(frame: &RenderFrame) -> Vec<SpriteInstance> {
    let (bullet_uv_off, bullet_uv_sz) = bullet_uv();
    let (fireball_uv_off, fireball_uv_sz) = fireball_uv();
    let (lightning_uv_off, lightning_uv_sz) = lightning_bullet_uv();
    let (whip_uv_off, whip_uv_sz) = whip_uv();
    let (particle_uv_off, particle_uv_sz) = particle_uv();
    let (gem_uv_off, gem_uv_sz) = gem_uv();
    let (potion_uv_off, potion_uv_sz) = potion_uv();
    let (magnet_uv_off, magnet_uv_sz) = magnet_uv();
    let (rock_uv_off, rock_uv_sz) = rock_bullet_uv();

    let mut instances: Vec<SpriteInstance> = Vec::with_capacity(
        frame.render_data.len()
            + frame.particle_data.len()
            + frame.item_data.len()
            + frame.obstacle_data.len(),
    );

    for &(x, y, kind, anim_frame) in &frame.render_data {
        let inst = match kind {
            0 => {
                let (uv_off, uv_sz) = player_anim_uv(anim_frame);
                SpriteInstance {
                    position: [x, y],
                    size: [SPRITE_SIZE, SPRITE_SIZE],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                }
            }
            1..=3 => {
                let sz = enemy_sprite_size(kind);
                let (uv_off, uv_sz) = enemy_anim_uv(kind, anim_frame);
                SpriteInstance {
                    position: [x, y],
                    size: [sz, sz],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                }
            }
            21..=23 => {
                let base = kind - ELITE_RENDER_KIND_OFFSET;
                let sz = enemy_sprite_size(base) * ELITE_SIZE_MULTIPLIER;
                let (uv_off, uv_sz) = enemy_anim_uv(base, anim_frame);
                SpriteInstance {
                    position: [x - sz * 0.1, y - sz * 0.1],
                    size: [sz, sz],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 0.4, 0.4, 1.0],
                }
            }
            crate::BULLET_KIND_NORMAL => SpriteInstance {
                position: [x - 8.0, y - 8.0],
                size: [16.0, 16.0],
                uv_offset: bullet_uv_off,
                uv_size: bullet_uv_sz,
                color_tint: [1.0, 1.0, 1.0, 1.0],
            },
            crate::BULLET_KIND_FIREBALL => SpriteInstance {
                position: [x - 11.0, y - 11.0],
                size: [22.0, 22.0],
                uv_offset: fireball_uv_off,
                uv_size: fireball_uv_sz,
                color_tint: [1.0, 1.0, 1.0, 1.0],
            },
            crate::BULLET_KIND_LIGHTNING => SpriteInstance {
                position: [x - 9.0, y - 9.0],
                size: [18.0, 18.0],
                uv_offset: lightning_uv_off,
                uv_size: lightning_uv_sz,
                color_tint: [1.0, 1.0, 1.0, 1.0],
            },
            crate::BULLET_KIND_WHIP => SpriteInstance {
                position: [x - 20.0, y - 10.0],
                size: [40.0, 20.0],
                uv_offset: whip_uv_off,
                uv_size: whip_uv_sz,
                color_tint: [1.0, 1.0, 1.0, 1.0],
            },
            11..=13 => {
                let sz = enemy_sprite_size(kind);
                let (uv_off, uv_sz) = enemy_anim_uv(kind, 0);
                SpriteInstance {
                    position: [x, y],
                    size: [sz, sz],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                }
            }
            crate::BULLET_KIND_ROCK => SpriteInstance {
                position: [x - 14.0, y - 14.0],
                size: [28.0, 28.0],
                uv_offset: rock_uv_off,
                uv_size: rock_uv_sz,
                color_tint: [1.0, 1.0, 1.0, 1.0],
            },
            _ => continue,
        };
        instances.push(inst);
        if instances.len() >= MAX_INSTANCES {
            break;
        }
    }

    for &(x, y, r, g, b, alpha, size) in &frame.particle_data {
        if instances.len() >= MAX_INSTANCES {
            break;
        }
        instances.push(SpriteInstance {
            position: [x - size / 2.0, y - size / 2.0],
            size: [size, size],
            uv_offset: particle_uv_off,
            uv_size: particle_uv_sz,
            color_tint: [r, g, b, alpha],
        });
    }

    for &(x, y, radius, kind) in &frame.obstacle_data {
        if instances.len() >= MAX_INSTANCES {
            break;
        }
        let (r, g, b) = if kind == 0 {
            (0.35, 0.55, 0.2)
        } else {
            (0.45, 0.45, 0.5)
        };
        let sz = radius * 2.0;
        instances.push(SpriteInstance {
            position: [x - radius, y - radius],
            size: [sz, sz],
            uv_offset: particle_uv_off,
            uv_size: particle_uv_sz,
            color_tint: [r, g, b, 1.0],
        });
    }

    for &(x, y, kind) in &frame.item_data {
        if instances.len() >= MAX_INSTANCES {
            break;
        }
        let (uv_off, uv_sz, sz) = match kind {
            RENDER_KIND_GEM => (gem_uv_off, gem_uv_sz, 20.0_f32),
            RENDER_KIND_POTION => (potion_uv_off, potion_uv_sz, 24.0_f32),
            RENDER_KIND_MAGNET => (magnet_uv_off, magnet_uv_sz, 28.0_f32),
            _ => continue,
        };
        instances.push(SpriteInstance {
            position: [x - sz / 2.0, y - sz / 2.0],
            size: [sz, sz],
            uv_offset: uv_off,
            uv_size: uv_sz,
            color_tint: [1.0, 1.0, 1.0, 1.0],
        });
    }

    instances
}
