//! Path: native/game_core/src/enemy.rs
//! Summary: 敵種類・HP・速度・スポーンロジックの共通定義

use crate::physics::rng::SimpleRng;

/// 敵の種類
#[derive(Clone, Copy, PartialEq, Debug, Default)]
#[repr(u8)]
pub enum EnemyKind {
    #[default]
    Slime = 0,
    Bat   = 1,
    Golem = 2,
}

impl EnemyKind {
    pub fn max_hp(&self) -> f32 {
        match self {
            Self::Slime => 30.0,
            Self::Bat => 15.0,
            Self::Golem => 150.0,
        }
    }

    pub fn speed(&self) -> f32 {
        match self {
            Self::Slime => 80.0,
            Self::Bat => 160.0,
            Self::Golem => 40.0,
        }
    }

    pub fn radius(&self) -> f32 {
        match self {
            Self::Slime => 20.0,
            Self::Bat => 12.0,
            Self::Golem => 32.0,
        }
    }

    pub fn exp_reward(&self) -> u32 {
        match self {
            Self::Slime => 5,
            Self::Bat => 3,
            Self::Golem => 20,
        }
    }

    pub fn damage_per_sec(&self) -> f32 {
        match self {
            Self::Slime => 20.0,
            Self::Bat => 10.0,
            Self::Golem => 40.0,
        }
    }

    /// レンダラーに渡す kind 値（0=player, 1=slime, 2=bat, 3=golem）
    pub fn render_kind(&self) -> u8 {
        match self {
            Self::Slime => 1,
            Self::Bat => 2,
            Self::Golem => 3,
        }
    }

    /// アニメーション FPS（main スタンドアロン用）
    pub fn anim_fps(&self) -> f32 {
        match self {
            Self::Slime => 6.0,
            Self::Bat => 12.0,
            Self::Golem => 4.0,
        }
    }

    /// アニメーションフレーム数（main スタンドアロン用）
    pub fn frame_count(&self) -> u8 {
        match self {
            Self::Slime => 4,
            Self::Bat => 2,
            Self::Golem => 2,
        }
    }

    /// 経過時間に応じた敵タイプ選択（main スタンドアロン用・難易度カーブ）
    pub fn for_elapsed(elapsed_secs: f32, rng: &mut SimpleRng) -> Self {
        if elapsed_secs < 60.0 {
            Self::Slime
        } else if elapsed_secs < 180.0 {
            if rng.next_u32() % 10 < 7 {
                Self::Slime
            } else {
                Self::Bat
            }
        } else if elapsed_secs < 360.0 {
            match rng.next_u32() % 10 {
                0..=4 => Self::Slime,
                5..=7 => Self::Bat,
                _ => Self::Golem,
            }
        } else {
            match rng.next_u32() % 3 {
                0 => Self::Slime,
                1 => Self::Bat,
                _ => Self::Golem,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enemy_max_hp() {
        assert!((EnemyKind::Slime.max_hp() - 30.0).abs() < 0.001);
        assert!((EnemyKind::Bat.max_hp() - 15.0).abs() < 0.001);
        assert!((EnemyKind::Golem.max_hp() - 150.0).abs() < 0.001);
    }

    #[test]
    fn enemy_speed() {
        assert!((EnemyKind::Slime.speed() - 80.0).abs() < 0.001);
        assert!((EnemyKind::Bat.speed() - 160.0).abs() < 0.001);
        assert!((EnemyKind::Golem.speed() - 40.0).abs() < 0.001);
    }

    #[test]
    fn enemy_radius() {
        assert!((EnemyKind::Slime.radius() - 20.0).abs() < 0.001);
        assert!((EnemyKind::Bat.radius() - 12.0).abs() < 0.001);
        assert!((EnemyKind::Golem.radius() - 32.0).abs() < 0.001);
    }

    #[test]
    fn enemy_exp_reward() {
        assert_eq!(EnemyKind::Slime.exp_reward(), 5);
        assert_eq!(EnemyKind::Bat.exp_reward(), 3);
        assert_eq!(EnemyKind::Golem.exp_reward(), 20);
    }

    #[test]
    fn enemy_render_kind() {
        assert_eq!(EnemyKind::Slime.render_kind(), 1);
        assert_eq!(EnemyKind::Bat.render_kind(), 2);
        assert_eq!(EnemyKind::Golem.render_kind(), 3);
    }

    #[test]
    fn for_elapsed_under_60_always_slime() {
        let mut rng = SimpleRng::new(42);
        for _ in 0..20 {
            assert_eq!(EnemyKind::for_elapsed(0.0, &mut rng), EnemyKind::Slime);
            assert_eq!(EnemyKind::for_elapsed(59.9, &mut rng), EnemyKind::Slime);
        }
    }
}
