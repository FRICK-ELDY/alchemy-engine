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

#[derive(Clone, Default)]
pub struct RenderFrame {
    pub render_data: Vec<(f32, f32, u8, u8)>,
    pub particle_data: Vec<(f32, f32, f32, f32, f32, f32, f32)>,
    pub item_data: Vec<(f32, f32, u8)>,
    pub obstacle_data: Vec<(f32, f32, f32, u8)>,
    pub camera_offset: (f32, f32),
    /// プレイヤーのスプライト位置（補間後に上書きされる専用フィールド）。
    /// `render_data[0]` への暗黙的な依存を排除するために独立させている。
    pub player_pos: (f32, f32),
    pub hud: HudData,
}

pub(crate) mod renderer;
pub mod window;

pub use renderer::{BossHudInfo, GamePhase, GameUiState, HudData, LoadDialogKind, Renderer};

#[cfg(feature = "headless")]
pub mod headless;
#[cfg(feature = "headless")]
pub use headless::HeadlessRenderer;
