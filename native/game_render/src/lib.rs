pub const BULLET_KIND_NORMAL: u8 = 4;
pub const BULLET_KIND_FIREBALL: u8 = 8;
pub const BULLET_KIND_LIGHTNING: u8 = 9;
pub const BULLET_KIND_WHIP: u8 = 10;
pub const BULLET_KIND_ROCK: u8 = 14;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UiAction {
    Start,
    Retry,
    Save,
    Load,
    LoadConfirm,
    LoadCancel,
    SkipLevelUp,
    ChooseWeapon,
}

impl UiAction {
    pub fn from_action_key(action: &str) -> Option<Self> {
        match action {
            "__start__" => Some(Self::Start),
            "__retry__" => Some(Self::Retry),
            "__save__" => Some(Self::Save),
            "__load__" => Some(Self::Load),
            "__load_confirm__" => Some(Self::LoadConfirm),
            "__load_cancel__" => Some(Self::LoadCancel),
            "__skip__" => Some(Self::SkipLevelUp),
            s if s.starts_with("__") => None,
            _ => Some(Self::ChooseWeapon),
        }
    }
}

/// 1フレーム分の描画命令。
/// Elixir 側（`game_content`）が組み立てて `push_render_frame` NIF 経由で送る。
#[derive(Clone, Debug)]
pub enum DrawCommand {
    /// プレイヤースプライト描画。
    /// `render_bridge.rs` が補間後にこのバリアントの座標を書き換える。
    /// `Sprite` と分離することで、補間対象を型安全に特定できる。
    PlayerSprite { x: f32, y: f32, frame: u8 },
    /// スプライト描画（敵・弾・ボスなど）
    Sprite {
        x: f32,
        y: f32,
        kind_id: u8,
        frame: u8,
    },
    /// パーティクル描画
    Particle {
        x: f32,
        y: f32,
        r: f32,
        g: f32,
        b: f32,
        alpha: f32,
        size: f32,
    },
    /// アイテム描画
    Item { x: f32, y: f32, kind: u8 },
    /// 障害物描画
    Obstacle {
        x: f32,
        y: f32,
        radius: f32,
        kind: u8,
    },
    /// 3D ボックス描画（R-5）
    Box3D {
        x: f32,
        y: f32,
        z: f32,
        half_w: f32,
        half_h: f32,
        half_d: f32,
        color: [f32; 4],
    },
    /// グリッド地面描画（R-5）
    GridPlane {
        size: f32,
        divisions: u32,
        color: [f32; 4],
    },
    /// スカイボックス（単色グラデーション）描画（R-5）
    Skybox {
        top_color: [f32; 4],
        bottom_color: [f32; 4],
    },
    /// 汎用スプライト描画（UV・サイズをコンテンツ側が直接指定する）。
    /// `Sprite` の kind_id → UV/サイズ変換テーブルを持たない新コンテンツ向け。
    SpriteRaw {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        /// アトラス UV オフセット（0.0〜1.0）
        uv_offset: [f32; 2],
        /// アトラス UV サイズ（0.0〜1.0）
        uv_size: [f32; 2],
        /// RGBA 乗算カラー
        color_tint: [f32; 4],
    },
}

/// カメラパラメータ。
#[derive(Clone, Debug)]
pub enum CameraParams {
    Camera2D { offset_x: f32, offset_y: f32 },
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

#[derive(Clone, Default)]
pub struct RenderFrame {
    pub commands: Vec<DrawCommand>,
    pub camera: CameraParams,
    pub hud: HudData,
}

pub(crate) mod renderer;
pub mod window;

pub use renderer::{
    BossHudInfo, GamePhase, GameUiState, HudData, LoadDialogKind, OverlayButton, OverlayData,
    Renderer, TitleOverlayData, WeaponSlotInfo,
};

#[cfg(feature = "headless")]
pub mod headless;
#[cfg(feature = "headless")]
pub use headless::HeadlessRenderer;
