//! shared-sim — 空間ティック実行の共有クレート（スキャフォールド）。
//!
//! 責務正本: `.workspace/0_docs/architecture-v2/shared-sim.md`
//!
//! # 保証すること
//! - 台帳範囲内での数値シミュレーション API の置き場
//! - host-server / client 予測補間 / Worker で同一クレートを使えること
//!
//! # 保証しないこと
//! - 権利・アカウント・Network Fan-out

#![deny(unsafe_code)]

/// 推奨権威ティック Hz（M1 / C1）。
pub const AUTHORITATIVE_TICK_HZ: u32 = 20;

/// 1 ティック分の経過時間（秒）。
pub const TICK_DT_SECS: f32 = 1.0 / AUTHORITATIVE_TICK_HZ as f32;

/// 空間ティック状態の最小プレースホルダ（SoA へ拡張予定）。
#[derive(Debug, Clone, Default)]
pub struct SimWorld {
    /// 進行したティック数。
    pub tick: u64,
    /// ビルトイン WorldManifest ID（例: `builtin.formula_test`）。未ロード時は空。
    pub manifest_id: String,
}

impl SimWorld {
    pub fn new(manifest_id: impl Into<String>) -> Self {
        Self {
            tick: 0,
            manifest_id: manifest_id.into(),
        }
    }

    /// 1 権威ティックを進める（物理・Formula は後続で接続）。
    pub fn step(&mut self, _dt: f32) {
        self.tick = self.tick.saturating_add(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn step_increments_tick() {
        let mut world = SimWorld::new("builtin.formula_test");
        world.step(TICK_DT_SECS);
        assert_eq!(world.tick, 1);
        assert_eq!(world.manifest_id, "builtin.formula_test");
    }

    #[test]
    fn default_tick_hz_is_20() {
        assert_eq!(AUTHORITATIVE_TICK_HZ, 20);
    }
}
