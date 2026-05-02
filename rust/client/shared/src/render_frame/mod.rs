//! 1 フレーム分の描画契約型（Elixir `contents` ↔ Rust `render` / Zenoh）。
//!
//! `render` クレート（wgpu 等）はここを参照し、protobuf デコードは `render_frame_proto` が担当する。

pub const BULLET_KIND_NORMAL: u8 = 4;
pub const BULLET_KIND_FIREBALL: u8 = 8;
pub const BULLET_KIND_LIGHTNING: u8 = 9;
pub const BULLET_KIND_WHIP: u8 = 10;
pub const BULLET_KIND_ROCK: u8 = 14;

// ── UI Canvas ────────────────────────────────────────────────────────

/// 1フレーム分の UI 全体。コンテンツ側が組み立てて渡す。
/// render はこのツリーを走査して描画するだけで、内容の意味を知らない。
#[derive(Clone, Default, Debug)]
pub struct UiCanvas {
    pub nodes: Vec<UiNode>,
}

/// UI ツリーの1ノード。位置・コンポーネント・子ノードを持つ。
#[derive(Clone, Debug)]
pub struct UiNode {
    pub rect: UiRect,
    pub component: UiComponent,
    pub children: Vec<UiNode>,
}

/// ノードの位置・サイズ定義。
#[derive(Clone, Debug)]
pub struct UiRect {
    pub anchor: UiAnchor,
    /// アンカー基点からのピクセルオフセット (x, y)
    pub offset: [f32; 2],
    pub size: UiSize,
}

/// アンカー（基準点）。egui の Align2 に対応する。
#[derive(Clone, Copy, Debug)]
pub enum UiAnchor {
    TopLeft,
    TopCenter,
    TopRight,
    MiddleLeft,
    Center,
    MiddleRight,
    BottomLeft,
    BottomCenter,
    BottomRight,
}

/// ノードのサイズ指定。
#[derive(Clone, Debug)]
pub enum UiSize {
    /// ピクセル固定サイズ
    Fixed(f32, f32),
    /// 子ノード・コンテンツに合わせて自動調整
    WrapContent,
}

/// UI コンポーネント。各ノードが持つ描画・レイアウト指示。
#[derive(Clone, Debug)]
pub enum UiComponent {
    /// 子ノードを横方向に並べるレイアウト
    HorizontalLayout { spacing: f32, padding: [f32; 4] },
    /// 子ノードを縦方向に並べるレイアウト
    VerticalLayout { spacing: f32, padding: [f32; 4] },
    /// テキストラベル
    Text {
        text: String,
        color: [f32; 4],
        size: f32,
        bold: bool,
    },
    /// 単色矩形（背景・枠など）
    Rect {
        color: [f32; 4],
        corner_radius: f32,
        /// 枠線 `(RGBA, 幅)`。`None` なら枠線なし
        border: Option<([f32; 4], f32)>,
    },
    /// プログレスバー
    ProgressBar {
        value: f32,
        max: f32,
        width: f32,
        height: f32,
        fg_color_high: [f32; 4],
        fg_color_mid: [f32; 4],
        fg_color_low: [f32; 4],
        bg_color: [f32; 4],
        corner_radius: f32,
    },
    /// ボタン。クリック時にアクション文字列を返す。
    Button {
        label: String,
        action: String,
        color: [f32; 4],
        min_width: f32,
        min_height: f32,
    },
    /// セパレータ（水平区切り線）
    Separator,
    /// 空白スペーサー（縦方向レイアウト内では高さ、横方向では幅として機能）
    Spacing { amount: f32 },
    /// ワールド座標上に浮かぶポップアップテキスト（スコア表示等）
    WorldText {
        world_x: f32,
        world_y: f32,
        world_z: f32,
        text: String,
        color: [f32; 4],
        lifetime: f32,
        max_lifetime: f32,
    },
    /// 画面全体を覆うフラッシュオーバーレイ
    ScreenFlash { color: [f32; 4] },
}

impl Default for UiRect {
    fn default() -> Self {
        Self {
            anchor: UiAnchor::TopLeft,
            offset: [0.0, 0.0],
            size: UiSize::WrapContent,
        }
    }
}

// ── MeshVertex（DrawCommand::GridPlaneVerts / MeshDef で使用）───────────

/// 3D メッシュ頂点（position + color）
#[repr(C)]
#[derive(Clone, Copy, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct MeshVertex {
    pub position: [f32; 3],
    pub color: [f32; 4],
}

mod draw_command;

pub use draw_command::DrawCommand;

// ── CameraParams ─────────────────────────────────────────────────────

/// カメラパラメータ。
#[derive(Clone, Debug)]
pub enum CameraParams {
    Camera2D {
        offset_x: f32,
        offset_y: f32,
    },
    /// 3D カメラ（R-5）
    Camera3D {
        eye: [f32; 3],
        target: [f32; 3],
        up: [f32; 3],
        fov_deg: f32,
        /// ニアクリップ面（デフォルト 0.1）
        near: f32,
        /// ファークリップ面（デフォルト 1000.0）
        far: f32,
    },
}

impl Default for CameraParams {
    fn default() -> Self {
        Self::Camera2D {
            offset_x: 0.0,
            offset_y: 0.0,
        }
    }
}

impl CameraParams {
    /// 2D カメラのワールド座標オフセットを返す。
    /// 3D カメラの場合は (0, 0) を返す（3D パイプラインは MVP 行列で処理するため不使用）。
    pub fn offset_xy(&self) -> (f32, f32) {
        match self {
            Self::Camera2D { offset_x, offset_y } => (*offset_x, *offset_y),
            Self::Camera3D { .. } => (0.0, 0.0),
        }
    }
}

// ── MeshDef（P3: Elixir 定義の受け手）──────────────────────────────────

/// Elixir 側で定義されたメッシュ。NIF / Zenoh 経由で `render` が受け取り create_buffer で登録する。
#[derive(Clone, Debug)]
pub struct MeshDef {
    pub name: String,
    pub vertices: Vec<MeshVertex>,
    pub indices: Vec<u32>,
}

// ── RenderFrame ──────────────────────────────────────────────────────

#[derive(Clone, Default)]
pub struct RenderFrame {
    pub commands: Vec<DrawCommand>,
    pub camera: CameraParams,
    pub ui: UiCanvas,
    /// カーソルグラブ状態の要求。`Some(true)` でグラブ、`Some(false)` で解放、`None` で変更なし。
    pub cursor_grab: Option<bool>,
    /// P3: メッシュ定義。非空の場合、パイプラインが登録して描画に使用する。
    pub mesh_definitions: Vec<MeshDef>,
    /// フレーム単位の効果音キュー（v1: `assets/` 始まりの相対パス）。クライアントが解決して再生。
    pub audio_cues: Vec<String>,
}
