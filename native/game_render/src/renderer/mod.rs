//! Path: native/game_render/src/renderer/mod.rs
//! Summary: wgpu によるスプライト描画・パイプライン・テクスチャ管理
//! 1.8: game_native から game_render へ分離移設。

use crate::DrawCommand;
use game_physics::constants::{BG_B, BG_G, BG_R, SPRITE_SIZE};
use game_physics::item::{RENDER_KIND_GEM, RENDER_KIND_MAGNET, RENDER_KIND_POTION};
use std::sync::Arc;
use wgpu::util::DeviceExt;
use winit::window::Window;
mod ui;
pub(crate) mod pipeline_3d;


pub(crate) const ELITE_RENDER_KIND_OFFSET: u8 = 20;
pub(crate) const ELITE_SIZE_MULTIPLIER: f32 = 1.2;

// ─── 頂点・インデックス ────────────────────────────────────────

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct Vertex {
    position: [f32; 2],
}

const VERTICES: &[Vertex] = &[
    Vertex {
        position: [0.0, 0.0],
    }, // 左上
    Vertex {
        position: [1.0, 0.0],
    }, // 右上
    Vertex {
        position: [1.0, 1.0],
    }, // 右下
    Vertex {
        position: [0.0, 1.0],
    }, // 左下
];

const INDICES: &[u16] = &[0, 1, 2, 0, 2, 3];

// ─── インスタンスデータ ────────────────────────────────────────

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
pub struct SpriteInstance {
    pub position: [f32; 2],   // ワールド座標（左上）
    pub size: [f32; 2],       // ピクセルサイズ
    pub uv_offset: [f32; 2],  // アトラス UV オフセット（0.0〜1.0）
    pub uv_size: [f32; 2],    // アトラス UV サイズ（0.0〜1.0）
    pub color_tint: [f32; 4], // RGBA 乗算カラー
}

// ─── アトラス UV 定数（1.2.9: 1600x64 px ボスエネミー対応アトラス）──
// アニメーションキャラクター（各 64x64、複数フレーム）:
//   [   0.. 255] プレイヤー歩行 4 フレーム
//   [ 256.. 511] Slime バウンス 4 フレーム
//   [ 512.. 639] Bat 羽ばたき 2 フレーム
//   [ 640.. 767] Golem 歩行 2 フレーム
// 静止スプライト（各 64x64）:
//   [ 768.. 831] 弾丸
//   [ 832.. 895] パーティクル
//   [ 896.. 959] 経験値宝石
//   [ 960..1023] 回復ポーション
//   [1024..1087] 磁石
//   [1088..1151] Fireball
//   [1152..1215] Lightning
//   [1216..1279] Whip
// 1.2.9: ボスエネミー（各 64x64）:
//   [1280..1343] Slime King
//   [1344..1407] Bat Lord
//   [1408..1471] Stone Golem
//   [1472..1535] 岩弾
const ATLAS_W: f32 = 1600.0;
const FRAME_W: f32 = 64.0; // 1 フレームの幅（px）

// アトラス X オフセット（px）— レイアウト変更時はここだけ修正
const PLAYER_ATLAS_OFFSET_X: f32 = 0.0;
const SLIME_ATLAS_OFFSET_X: f32 = 256.0;
const BAT_ATLAS_OFFSET_X: f32 = 512.0;
const GOLEM_ATLAS_OFFSET_X: f32 = 640.0;
const BULLET_ATLAS_OFFSET_X: f32 = 768.0;
const PARTICLE_ATLAS_OFFSET_X: f32 = 832.0;
const GEM_ATLAS_OFFSET_X: f32 = 896.0;
const POTION_ATLAS_OFFSET_X: f32 = 960.0;
const MAGNET_ATLAS_OFFSET_X: f32 = 1024.0;
const FIREBALL_ATLAS_OFFSET_X: f32 = 1088.0;
const LIGHTNING_ATLAS_OFFSET_X: f32 = 1152.0;
const WHIP_ATLAS_OFFSET_X: f32 = 1216.0;
const SLIME_KING_ATLAS_OFFSET_X: f32 = 1280.0;
const BAT_LORD_ATLAS_OFFSET_X: f32 = 1344.0;
const STONE_GOLEM_ATLAS_OFFSET_X: f32 = 1408.0;
const ROCK_BULLET_ATLAS_OFFSET_X: f32 = 1472.0;

/// プレイヤーのアニメーション UV（フレーム番号 0〜3）
pub fn player_anim_uv(frame: u8) -> ([f32; 2], [f32; 2]) {
    let x = PLAYER_ATLAS_OFFSET_X + (frame as f32) * FRAME_W;
    ([x / ATLAS_W, 0.0], [FRAME_W / ATLAS_W, 1.0])
}
/// Slime のアニメーション UV（フレーム番号 0〜3）
pub fn slime_anim_uv(frame: u8) -> ([f32; 2], [f32; 2]) {
    let x = SLIME_ATLAS_OFFSET_X + (frame as f32) * FRAME_W;
    ([x / ATLAS_W, 0.0], [FRAME_W / ATLAS_W, 1.0])
}
/// Bat のアニメーション UV（フレーム番号 0〜1）
pub fn bat_anim_uv(frame: u8) -> ([f32; 2], [f32; 2]) {
    let frame2 = (frame % 2) as f32;
    let x = BAT_ATLAS_OFFSET_X + frame2 * FRAME_W;
    ([x / ATLAS_W, 0.0], [FRAME_W / ATLAS_W, 1.0])
}
/// Golem のアニメーション UV（フレーム番号 0〜1）
pub fn golem_anim_uv(frame: u8) -> ([f32; 2], [f32; 2]) {
    let frame2 = (frame % 2) as f32;
    let x = GOLEM_ATLAS_OFFSET_X + frame2 * FRAME_W;
    ([x / ATLAS_W, 0.0], [FRAME_W / ATLAS_W, 1.0])
}
pub fn bullet_uv() -> ([f32; 2], [f32; 2]) {
    (
        [BULLET_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn particle_uv() -> ([f32; 2], [f32; 2]) {
    (
        [PARTICLE_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn gem_uv() -> ([f32; 2], [f32; 2]) {
    (
        [GEM_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn potion_uv() -> ([f32; 2], [f32; 2]) {
    (
        [POTION_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn magnet_uv() -> ([f32; 2], [f32; 2]) {
    (
        [MAGNET_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn fireball_uv() -> ([f32; 2], [f32; 2]) {
    (
        [FIREBALL_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn lightning_bullet_uv() -> ([f32; 2], [f32; 2]) {
    (
        [LIGHTNING_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn whip_uv() -> ([f32; 2], [f32; 2]) {
    (
        [WHIP_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
/// 1.2.9: ボス UV
pub fn slime_king_uv() -> ([f32; 2], [f32; 2]) {
    (
        [SLIME_KING_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn bat_lord_uv() -> ([f32; 2], [f32; 2]) {
    (
        [BAT_LORD_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn stone_golem_uv() -> ([f32; 2], [f32; 2]) {
    (
        [STONE_GOLEM_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}
pub fn rock_bullet_uv() -> ([f32; 2], [f32; 2]) {
    (
        [ROCK_BULLET_ATLAS_OFFSET_X / ATLAS_W, 0.0],
        [FRAME_W / ATLAS_W, 1.0],
    )
}

// ─── 画面サイズ Uniform ────────────────────────────────────────

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct ScreenUniform {
    half_size: [f32; 2],
    _pad: [f32; 2],
}

impl ScreenUniform {
    fn new(width: u32, height: u32) -> Self {
        Self {
            half_size: [width as f32 / 2.0, height as f32 / 2.0],
            _pad: [0.0; 2],
        }
    }
}

// ─── カメラ Uniform（1.2.5: プレイヤー追従スクロール）──────

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct CameraUniform {
    offset: [f32; 2],
    _pad: [f32; 2],
}

impl CameraUniform {
    fn new(offset_x: f32, offset_y: f32) -> Self {
        Self {
            offset: [offset_x, offset_y],
            _pad: [0.0; 2],
        }
    }
}

// ─── インスタンスバッファの最大容量 ────────────────────────────
// Player 1 + Boss 1 + Enemies 10000 + Bullets 2000 + Particles 2000 + Items 500 + Obstacles 8
// = 14510
// Enemies 内訳: うちエリート敵は最大 30% = 3000 体（kind: 21/22/23）。
//               エリート敵は通常敵スロットを共有するため Enemies 合計は変わらない。
// Obstacles: MapLoader の最大マップ（:forest）で 8 体。
pub(crate) const MAX_INSTANCES: usize = 14510;

// 敵タイプ別のスプライトサイズ（px）
// kind: 1=slime(40px), 2=bat(24px), 3=golem(64px), 4=ghost(32px), 5=skeleton(40px)
// 1.2.9: boss kind: 11=SlimeKing(96px), 12=BatLord(96px), 13=StoneGolem(128px)
pub(crate) fn enemy_sprite_size(kind: u8) -> f32 {
    match kind {
        2 => 24.0,   // Bat: 小さい
        3 => 64.0,   // Golem: 大きい
        4 => 32.0,   // Ghost
        5 => 40.0,   // Skeleton
        11 => 96.0,  // Slime King: 巨大
        12 => 96.0,  // Bat Lord: 巨大
        13 => 128.0, // Stone Golem: 最大
        _ => 40.0,   // Slime: 基本
    }
}

/// Skeleton 用 UV（Golem と同スロットでプレースホルダー）
/// TODO: 専用スプライトスロットを確保するまでの暫定措置。Golem の UV を流用中。
fn skeleton_anim_uv(frame: u8) -> ([f32; 2], [f32; 2]) {
    golem_anim_uv(frame)
}
/// Ghost 用 UV（Bat と同スロットでプレースホルダー）
/// TODO: 専用スプライトスロットを確保するまでの暫定措置。Bat の UV を流用中。
fn ghost_anim_uv(frame: u8) -> ([f32; 2], [f32; 2]) {
    bat_anim_uv(frame)
}

/// 1.2.8/1.2.9: アニメーションフレームを考慮した敵 UV（ボスは静止スプライト）
pub(crate) fn enemy_anim_uv(kind: u8, frame: u8) -> ([f32; 2], [f32; 2]) {
    match kind {
        2 => bat_anim_uv(frame),
        3 => golem_anim_uv(frame),
        4 => ghost_anim_uv(frame),
        5 => skeleton_anim_uv(frame),
        11 => slime_king_uv(),
        12 => bat_lord_uv(),
        13 => stone_golem_uv(),
        _ => slime_anim_uv(frame),
    }
}


/// ロードダイアログの種別
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum LoadDialogKind {
    /// セーブデータが存在する場合の「ロードしますか？」確認ダイアログ
    Confirm,
    /// セーブデータが存在しない場合の「セーブデータなし」通知ダイアログ
    NoSaveData,
}

/// 1.5.3: セーブ・ロード用 UI 状態
#[derive(Default)]
pub struct GameUiState {
    /// トースト表示 (メッセージ, 残り秒数)
    pub save_toast: Option<(String, f32)>,
    /// ロードダイアログ: None=閉, Some(Confirm)=確認待ち, Some(NoSaveData)=「セーブデータなし」
    pub load_dialog: Option<LoadDialogKind>,
    pub has_save: bool,
    /// ボタンクリックでセットするアクション（毎フレーム消費）
    pub pending_action: Option<String>,
}

// ─── Renderer ─────────────────────────────────────────────────

pub struct Renderer {
    surface: wgpu::Surface<'static>,
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    config: wgpu::SurfaceConfiguration,
    render_pipeline: wgpu::RenderPipeline,
    vertex_buffer: wgpu::Buffer,
    index_buffer: wgpu::Buffer,
    instance_buffer: wgpu::Buffer,
    instance_count: u32,
    bind_group: wgpu::BindGroup,
    screen_uniform_buf: wgpu::Buffer,
    screen_bind_group: wgpu::BindGroup,
    // 1.2.5: カメラ Uniform
    camera_uniform_buf: wgpu::Buffer,
    camera_bind_group: wgpu::BindGroup,
    // R-5: 3D パイプライン
    pipeline_3d: pipeline_3d::Pipeline3D,
    // egui
    egui_ctx: egui::Context,
    egui_renderer: egui_wgpu::Renderer,
    egui_winit: egui_winit::State,
    // FPS 計測
    frame_count: u32,
    fps_timer: std::time::Instant,
    pub current_fps: f32,
}

impl Renderer {
    /// 1.7.2: atlas_bytes を引数で受け取る。1.7.3 で asset が game_native に移動したら
    /// 呼び出し元（render_thread 等）で AssetLoader から取得して渡す。
    pub async fn new(window: Arc<Window>, atlas_bytes: &[u8]) -> Self {
        let instance = wgpu::Instance::default();
        let surface = instance
            .create_surface(window.clone())
            .expect("サーフェスの作成に失敗しました");

        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: Some(&surface),
                ..Default::default()
            })
            .await
            .expect("アダプターの取得に失敗しました");

        let (device_raw, queue_raw) = adapter
            .request_device(&wgpu::DeviceDescriptor::default(), None)
            .await
            .expect("デバイスとキューの取得に失敗しました");
        let device = Arc::new(device_raw);
        let queue = Arc::new(queue_raw);

        let size = window.inner_size();
        let config = surface
            .get_default_config(&adapter, size.width, size.height)
            .expect("サーフェス設定の取得に失敗しました");
        surface.configure(&device, &config);

        // ─── テクスチャアトラス（1.7.2: atlas_bytes を引数で受け取る。1.7.3 で AssetLoader 利用）──
        let atlas_image = image::load_from_memory(atlas_bytes)
            .expect("atlas.png の読み込みに失敗しました")
            .to_rgba8();
        let atlas_size = wgpu::Extent3d {
            width: atlas_image.width(),
            height: atlas_image.height(),
            depth_or_array_layers: 1,
        };
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Atlas Texture"),
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
            label: Some("Atlas Sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Nearest,
            min_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        // ─── バインドグループ group(0): テクスチャ ───────────────
        let texture_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Texture Bind Group Layout"),
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
            label: Some("Texture Bind Group"),
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

        // ─── バインドグループ group(1): 画面サイズ Uniform ──────
        let screen_uniform = ScreenUniform::new(size.width, size.height);
        let screen_uniform_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Screen Uniform Buffer"),
            contents: bytemuck::bytes_of(&screen_uniform),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let screen_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Screen Bind Group Layout"),
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
            label: Some("Screen Bind Group"),
            layout: &screen_bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: screen_uniform_buf.as_entire_binding(),
            }],
        });

        // ─── バインドグループ group(2): カメラ Uniform（1.2.5）─
        let camera_uniform = CameraUniform::new(0.0, 0.0);
        let camera_uniform_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Camera Uniform Buffer"),
            contents: bytemuck::bytes_of(&camera_uniform),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let camera_bind_group_layout =
            device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("Camera Bind Group Layout"),
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
            label: Some("Camera Bind Group"),
            layout: &camera_bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: camera_uniform_buf.as_entire_binding(),
            }],
        });

        // ─── シェーダー・パイプライン ────────────────────────────
        let shader_source = include_str!("shaders/sprite.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Sprite Shader"),
            source: wgpu::ShaderSource::Wgsl(shader_source.into()),
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Sprite Pipeline Layout"),
            bind_group_layouts: &[
                &texture_bind_group_layout,
                &screen_bind_group_layout,
                &camera_bind_group_layout,
            ],
            push_constant_ranges: &[],
        });

        let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Sprite Pipeline"),
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
                        array_stride: std::mem::size_of::<SpriteInstance>() as wgpu::BufferAddress,
                        step_mode: wgpu::VertexStepMode::Instance,
                        attributes: &wgpu::vertex_attr_array![
                            1 => Float32x2, // i_position
                            2 => Float32x2, // i_size
                            3 => Float32x2, // i_uv_offset
                            4 => Float32x2, // i_uv_size
                            5 => Float32x4, // i_color_tint
                        ],
                    },
                ],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: config.format,
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

        // ─── 頂点・インデックスバッファ ──────────────────────────
        let vertex_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Vertex Buffer"),
            contents: bytemuck::cast_slice(VERTICES),
            usage: wgpu::BufferUsages::VERTEX,
        });
        let index_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Index Buffer"),
            contents: bytemuck::cast_slice(INDICES),
            usage: wgpu::BufferUsages::INDEX,
        });

        // ─── インスタンスバッファ（動的・最大 MAX_INSTANCES 体）──
        let instance_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Instance Buffer"),
            size: (std::mem::size_of::<SpriteInstance>() * MAX_INSTANCES) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // ─── egui 初期化 ─────────────────────────────────────────
        let egui_ctx = egui::Context::default();
        let egui_renderer = egui_wgpu::Renderer::new(&device, config.format, None, 1, false);
        let egui_winit = egui_winit::State::new(
            egui_ctx.clone(),
            egui::ViewportId::ROOT,
            &window,
            None,
            None,
            None,
        );

        // ─── R-5: 3D パイプライン初期化 ──────────────────────────
        let pipeline_3d = pipeline_3d::Pipeline3D::new(
            Arc::clone(&device),
            Arc::clone(&queue),
            config.format,
            size.width,
            size.height,
        );

        Self {
            surface,
            device,
            queue,
            config,
            render_pipeline,
            vertex_buffer,
            index_buffer,
            instance_buffer,
            instance_count: 0,
            bind_group,
            screen_uniform_buf,
            screen_bind_group,
            camera_uniform_buf,
            camera_bind_group,
            pipeline_3d,
            egui_ctx,
            egui_renderer,
            egui_winit,
            frame_count: 0,
            fps_timer: std::time::Instant::now(),
            current_fps: 0.0,
        }
    }

    /// winit のウィンドウイベントを egui に転送する
    pub fn handle_window_event(
        &mut self,
        window: &Window,
        event: &winit::event::WindowEvent,
    ) -> bool {
        self.egui_winit.on_window_event(window, event).consumed
    }

    /// `RenderFrame` の `DrawCommand` リストからインスタンスを構築して GPU バッファを更新する。
    pub fn update_instances(&mut self, frame: &crate::RenderFrame) {
        let (offset_x, offset_y) = frame.camera.offset_xy();
        let cam_uniform = CameraUniform::new(offset_x, offset_y);
        self.queue.write_buffer(
            &self.camera_uniform_buf,
            0,
            bytemuck::bytes_of(&cam_uniform),
        );

        let instances = build_sprite_instances(&frame.commands);
        self.instance_count = instances.len() as u32;

        if !instances.is_empty() {
            self.queue
                .write_buffer(&self.instance_buffer, 0, bytemuck::cast_slice(&instances));
        }
    }

    pub fn resize(&mut self, new_width: u32, new_height: u32) {
        if new_width == 0 || new_height == 0 {
            return;
        }
        self.config.width = new_width;
        self.config.height = new_height;
        self.surface.configure(&self.device, &self.config);

        let screen_uniform = ScreenUniform::new(new_width, new_height);
        self.queue.write_buffer(
            &self.screen_uniform_buf,
            0,
            bytemuck::bytes_of(&screen_uniform),
        );

        self.pipeline_3d.resize(new_width, new_height);
    }

    /// UI を描画し、ボタンが押された場合はアクション文字列を返す。
    /// ui_state でセーブ/ロードダイアログ・トーストを制御する。
    /// R-5: `CameraParams::Camera3D` の場合は 3D パイプラインを使用する。
    pub fn render(
        &mut self,
        window: &Window,
        ui: &crate::UiCanvas,
        camera: &crate::CameraParams,
        commands: &[DrawCommand],
        ui_state: &mut GameUiState,
    ) -> Option<String> {
        // ─── FPS 計測 ────────────────────────────────────────────
        self.frame_count += 1;
        let elapsed = self.fps_timer.elapsed();
        if elapsed.as_secs_f32() >= 1.0 {
            self.current_fps = self.frame_count as f32 / elapsed.as_secs_f32();
            self.frame_count = 0;
            self.fps_timer = std::time::Instant::now();
        }

        // ─── サーフェス取得 ──────────────────────────────────────
        let output = match self.surface.get_current_texture() {
            Ok(t) => t,
            Err(wgpu::SurfaceError::Lost | wgpu::SurfaceError::Outdated) => {
                self.surface.configure(&self.device, &self.config);
                return None;
            }
            Err(e) => {
                eprintln!("Surface error: {e:?}");
                return None;
            }
        };

        let view = output.texture.create_view(&Default::default());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Render Encoder"),
            });

        // ─── スプライト描画パス ──────────────────────────────────
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Sprite Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
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

            if self.instance_count > 0 {
                pass.set_pipeline(&self.render_pipeline);
                pass.set_bind_group(0, &self.bind_group, &[]);
                pass.set_bind_group(1, &self.screen_bind_group, &[]);
                pass.set_bind_group(2, &self.camera_bind_group, &[]);
                pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
                pass.set_vertex_buffer(1, self.instance_buffer.slice(..));
                pass.set_index_buffer(self.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
                pass.draw_indexed(0..INDICES.len() as u32, 0, 0..self.instance_count);
            }
        }

        // ─── R-5: 3D パス ────────────────────────────────────────
        // Camera3D 以外が渡された場合は pipeline_3d.render() 内で早期リターンする。
        self.pipeline_3d
            .render(&mut encoder, &view, commands, camera);

        // ─── egui HUD パス ───────────────────────────────────────
        let raw_input = self.egui_winit.take_egui_input(window);
        let mut chosen_weapon: Option<String> = None;
        let full_output = self.egui_ctx.run(raw_input, |ctx| {
            chosen_weapon = ui::render_ui_canvas(ctx, ui, camera, self.current_fps, ui_state);
        });

        self.egui_winit
            .handle_platform_output(window, full_output.platform_output);

        let tris = self
            .egui_ctx
            .tessellate(full_output.shapes, full_output.pixels_per_point);

        for (id, delta) in full_output.textures_delta.set {
            self.egui_renderer
                .update_texture(&self.device, &self.queue, id, &delta);
        }

        let screen_desc = egui_wgpu::ScreenDescriptor {
            size_in_pixels: [self.config.width, self.config.height],
            pixels_per_point: full_output.pixels_per_point,
        };
        self.egui_renderer.update_buffers(
            &self.device,
            &self.queue,
            &mut encoder,
            &tris,
            &screen_desc,
        );

        // egui_renderer.render() は RenderPass を消費するため、別スコープで処理する
        {
            let render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("egui Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
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
            // egui-wgpu 0.31 では render() が RenderPass を所有する形に変更された
            self.egui_renderer
                .render(&mut render_pass.forget_lifetime(), &tris, &screen_desc);
        }

        for id in full_output.textures_delta.free {
            self.egui_renderer.free_texture(&id);
        }

        self.queue.submit([encoder.finish()]);
        output.present();

        chosen_weapon
    }
}

/// `DrawCommand` リストから `SpriteInstance` リストを構築する。
/// `Renderer::update_instances` と `HeadlessRenderer::render_frame_offscreen` の両方から使用する。
pub(crate) fn build_sprite_instances(commands: &[DrawCommand]) -> Vec<SpriteInstance> {
    let mut instances: Vec<SpriteInstance> = Vec::with_capacity(commands.len());

    for cmd in commands {
        if instances.len() >= MAX_INSTANCES {
            break;
        }
        let Some(inst) = sprite_instance_from_command(cmd) else {
            continue;
        };
        instances.push(inst);
    }

    instances
}

/// `DrawCommand` 1件を `SpriteInstance` に変換する。
/// 描画対象外のコマンド（未知の kind_id 等）は `None` を返す。
fn sprite_instance_from_command(cmd: &DrawCommand) -> Option<SpriteInstance> {
    match *cmd {
        DrawCommand::PlayerSprite {
            x,
            y,
            frame: anim_frame,
        } => {
            let (uv_off, uv_sz) = player_anim_uv(anim_frame);
            Some(SpriteInstance {
                position: [x, y],
                size: [SPRITE_SIZE, SPRITE_SIZE],
                uv_offset: uv_off,
                uv_size: uv_sz,
                color_tint: [1.0, 1.0, 1.0, 1.0],
            })
        }
        DrawCommand::Sprite {
            x,
            y,
            kind_id: kind,
            frame: anim_frame,
        } => match kind {
            1..=3 => {
                let sz = enemy_sprite_size(kind);
                let (uv_off, uv_sz) = enemy_anim_uv(kind, anim_frame);
                Some(SpriteInstance {
                    position: [x, y],
                    size: [sz, sz],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                })
            }
            21..=23 => {
                let base = kind - ELITE_RENDER_KIND_OFFSET;
                let sz = enemy_sprite_size(base) * ELITE_SIZE_MULTIPLIER;
                let (uv_off, uv_sz) = enemy_anim_uv(base, anim_frame);
                Some(SpriteInstance {
                    position: [x - sz * 0.1, y - sz * 0.1],
                    size: [sz, sz],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 0.4, 0.4, 1.0],
                })
            }
            crate::BULLET_KIND_NORMAL => {
                let (uv_off, uv_sz) = bullet_uv();
                Some(SpriteInstance {
                    position: [x - 8.0, y - 8.0],
                    size: [16.0, 16.0],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                })
            }
            crate::BULLET_KIND_FIREBALL => {
                let (uv_off, uv_sz) = fireball_uv();
                Some(SpriteInstance {
                    position: [x - 11.0, y - 11.0],
                    size: [22.0, 22.0],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                })
            }
            crate::BULLET_KIND_LIGHTNING => {
                let (uv_off, uv_sz) = lightning_bullet_uv();
                Some(SpriteInstance {
                    position: [x - 9.0, y - 9.0],
                    size: [18.0, 18.0],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                })
            }
            crate::BULLET_KIND_WHIP => {
                let (uv_off, uv_sz) = whip_uv();
                Some(SpriteInstance {
                    position: [x - 20.0, y - 10.0],
                    size: [40.0, 20.0],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                })
            }
            11..=13 => {
                let sz = enemy_sprite_size(kind);
                let (uv_off, uv_sz) = enemy_anim_uv(kind, 0);
                Some(SpriteInstance {
                    position: [x, y],
                    size: [sz, sz],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                })
            }
            crate::BULLET_KIND_ROCK => {
                let (uv_off, uv_sz) = rock_bullet_uv();
                Some(SpriteInstance {
                    position: [x - 14.0, y - 14.0],
                    size: [28.0, 28.0],
                    uv_offset: uv_off,
                    uv_size: uv_sz,
                    color_tint: [1.0, 1.0, 1.0, 1.0],
                })
            }
            _ => None,
        },
        DrawCommand::Particle {
            x,
            y,
            r,
            g,
            b,
            alpha,
            size,
        } => {
            let (uv_off, uv_sz) = particle_uv();
            Some(SpriteInstance {
                position: [x - size / 2.0, y - size / 2.0],
                size: [size, size],
                uv_offset: uv_off,
                uv_size: uv_sz,
                color_tint: [r, g, b, alpha],
            })
        }
        DrawCommand::Obstacle { x, y, radius, kind } => {
            let (r, g, b) = if kind == 0 {
                (0.35_f32, 0.55_f32, 0.2_f32)
            } else {
                (0.45_f32, 0.45_f32, 0.5_f32)
            };
            let sz = radius * 2.0;
            let (uv_off, uv_sz) = particle_uv();
            Some(SpriteInstance {
                position: [x - radius, y - radius],
                size: [sz, sz],
                uv_offset: uv_off,
                uv_size: uv_sz,
                color_tint: [r, g, b, 1.0],
            })
        }
        DrawCommand::Item { x, y, kind } => {
            let (uv, sz) = match kind {
                RENDER_KIND_GEM => (gem_uv(), 20.0_f32),
                RENDER_KIND_POTION => (potion_uv(), 24.0_f32),
                RENDER_KIND_MAGNET => (magnet_uv(), 28.0_f32),
                _ => return None,
            };
            let (uv_off, uv_sz) = uv;
            Some(SpriteInstance {
                position: [x - sz / 2.0, y - sz / 2.0],
                size: [sz, sz],
                uv_offset: uv_off,
                uv_size: uv_sz,
                color_tint: [1.0, 1.0, 1.0, 1.0],
            })
        }
        DrawCommand::SpriteRaw {
            x,
            y,
            width,
            height,
            uv_offset,
            uv_size,
            color_tint,
        } => Some(SpriteInstance {
            position: [x, y],
            size: [width, height],
            uv_offset,
            uv_size,
            color_tint,
        }),
        // 3D コマンドはスプライトパイプラインでは描画しない
        DrawCommand::Box3D { .. } | DrawCommand::GridPlane { .. } | DrawCommand::Skybox { .. } => {
            None
        }
    }
}
