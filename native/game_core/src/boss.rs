//! Path: native/game_core/src/boss.rs
//! Summary: ボス種類・HP・行動の共通定義

/// ボスの種類（セーブデータ互換のため #[repr(u8)] と明示値で固定）
#[derive(Clone, Copy, PartialEq, Debug)]
#[repr(u8)]
pub enum BossKind {
    SlimeKing   = 0,
    BatLord     = 1,
    StoneGolem  = 2,
}

impl BossKind {
    /// セーブデータからのデシリアライズ用。未知の ID は None。
    pub fn from_u8(id: u8) -> Option<Self> {
        match id {
            0 => Some(Self::SlimeKing),
            1 => Some(Self::BatLord),
            2 => Some(Self::StoneGolem),
            _ => None,
        }
    }
}

impl BossKind {
    pub fn max_hp(&self) -> f32 {
        match self {
            Self::SlimeKing => 1000.0,
            Self::BatLord => 2000.0,
            Self::StoneGolem => 5000.0,
        }
    }

    pub fn speed(&self) -> f32 {
        match self {
            Self::SlimeKing => 60.0,
            Self::BatLord => 200.0,
            Self::StoneGolem => 30.0,
        }
    }

    pub fn radius(&self) -> f32 {
        match self {
            Self::SlimeKing => 48.0,
            Self::BatLord => 48.0,
            Self::StoneGolem => 64.0,
        }
    }

    pub fn exp_reward(&self) -> u32 {
        match self {
            Self::SlimeKing => 200,
            Self::BatLord => 400,
            Self::StoneGolem => 800,
        }
    }

    pub fn damage_per_sec(&self) -> f32 {
        match self {
            Self::SlimeKing => 30.0,
            Self::BatLord => 50.0,
            Self::StoneGolem => 80.0,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::SlimeKing => "Slime King",
            Self::BatLord => "Bat Lord",
            Self::StoneGolem => "Stone Golem",
        }
    }

    /// render_kind（renderer の kind 番号）
    pub fn render_kind(&self) -> u8 {
        match self {
            Self::SlimeKing => 11,
            Self::BatLord => 12,
            Self::StoneGolem => 13,
        }
    }

    /// 特殊行動のインターバル（秒）
    pub fn special_interval(&self) -> f32 {
        match self {
            Self::SlimeKing => 5.0,
            Self::BatLord => 4.0,
            Self::StoneGolem => 6.0,
        }
    }
}
