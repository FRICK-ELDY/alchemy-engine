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
/// コンテンツ固有の概念（スプライト種別・パーティクル等）を
/// `game_nif` 層が知らなくて済むよう、将来的には Elixir 側が組み立てて送る。
/// Phase R-1 では `render_snapshot.rs` がこれを生成する（既存の動作を維持）。
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
}

/// カメラパラメータ。Phase R-1 では 2D のみ使用。
#[derive(Clone, Debug)]
pub enum CameraParams {
    Camera2D { offset_x: f32, offset_y: f32 },
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
    /// カメラのワールド座標オフセットを返す。
    /// 2D カメラでは (offset_x, offset_y)。将来 3D バリアントが追加された場合は
    /// 投影後の 2D オフセットに相当する値を返すよう拡張する。
    pub fn offset_xy(&self) -> (f32, f32) {
        match self {
            Self::Camera2D { offset_x, offset_y } => (*offset_x, *offset_y),
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

pub use renderer::{BossHudInfo, GamePhase, GameUiState, HudData, LoadDialogKind, Renderer};

#[cfg(feature = "headless")]
pub mod headless;
#[cfg(feature = "headless")]
pub use headless::HeadlessRenderer;
