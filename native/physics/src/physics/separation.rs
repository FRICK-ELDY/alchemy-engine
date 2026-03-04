//! Path: native/game_core/src/physics/separation.rs
//! Summary: 敵同士の重なり解消（Separation）トレイトと適用ロジック

use super::spatial_hash::SpatialHash;

// ─── 分離トレイト ──────────────────────────────────────────────
/// 敵同士の重なりを解消する分離（Separation）パスを提供するトレイト。
///
/// 実装側は各フィールドへのアクセサと、作業バッファへの可変参照を提供する。
/// バッファは EnemyWorld に持たせて毎フレーム再利用し、アロケーションを回避する。
pub trait EnemySeparation {
    fn enemy_count(&self) -> usize;
    fn is_alive(&self, i: usize) -> bool;
    fn pos_x(&self, i: usize) -> f32;
    fn pos_y(&self, i: usize) -> f32;
    fn add_pos_x(&mut self, i: usize, v: f32);
    fn add_pos_y(&mut self, i: usize, v: f32);
    fn sep_buf_x(&mut self) -> &mut Vec<f32>;
    fn sep_buf_y(&mut self) -> &mut Vec<f32>;
    /// 近隣クエリ結果の再利用バッファ（毎フレームのヒープアロケーションを回避）
    fn neighbor_buf(&mut self) -> &mut Vec<usize>;
}

/// 分離パスを実行する。
///
/// アルゴリズム:
///   1. Spatial Hash で近隣の敵を列挙
///   2. 重なっているペアに対して押し出しベクトルを計算しバッファに蓄積
///   3. バッファを位置に適用
///
/// rayon で並列化できないため（書き込みが衝突する）シングルスレッドで処理する。
/// Spatial Hash により計算量は O(n) に近い。
pub fn apply_separation<W: EnemySeparation>(
    world: &mut W,
    separation_radius: f32,
    separation_force: f32,
    dt: f32,
) {
    let len = world.enemy_count();
    if len < 2 {
        return;
    }

    // バッファをゼロクリアして再利用（アロケーションなし）
    world.sep_buf_x().iter_mut().for_each(|v| *v = 0.0);
    world.sep_buf_y().iter_mut().for_each(|v| *v = 0.0);

    // Spatial Hash を構築（生存敵のみ）
    let mut hash = SpatialHash::new(separation_radius);
    for i in 0..len {
        if world.is_alive(i) {
            hash.insert(i, world.pos_x(i), world.pos_y(i));
        }
    }

    for i in 0..len {
        if !world.is_alive(i) {
            continue;
        }
        let ix = world.pos_x(i);
        let iy = world.pos_y(i);

        // neighbor_buf を再利用してヒープアロケーションを回避
        hash.query_nearby_into(ix, iy, separation_radius, world.neighbor_buf());
        // buf の借用を解放するため長さだけ取り出してインデックスアクセス
        let nb_len = world.neighbor_buf().len();
        for ni in 0..nb_len {
            let j = world.neighbor_buf()[ni];
            if j <= i || !world.is_alive(j) {
                // j <= i: 各ペアを一度だけ処理（両方向に適用するため）
                continue;
            }
            let jx = world.pos_x(j);
            let jy = world.pos_y(j);

            let dx = ix - jx;
            let dy = iy - jy;
            let dist_sq = dx * dx + dy * dy;

            if dist_sq < separation_radius * separation_radius && dist_sq > 1e-6 {
                let dist = dist_sq.sqrt();
                let overlap = separation_radius - dist;
                let force = overlap * separation_force * dt;
                let nx = (dx / dist) * force;
                let ny = (dy / dist) * force;
                world.sep_buf_x()[i] += nx;
                world.sep_buf_y()[i] += ny;
                world.sep_buf_x()[j] -= nx;
                world.sep_buf_y()[j] -= ny;
            }
        }
    }

    // バッファを位置に適用
    for i in 0..len {
        if world.is_alive(i) {
            let sx = world.sep_buf_x()[i];
            let sy = world.sep_buf_y()[i];
            world.add_pos_x(i, sx);
            world.add_pos_y(i, sy);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// テスト用の最小限 EnemySeparation 実装
    struct TestWorld {
        positions_x: Vec<f32>,
        positions_y: Vec<f32>,
        alive: Vec<bool>,
        sep_x: Vec<f32>,
        sep_y: Vec<f32>,
        neighbor_buf: Vec<usize>,
    }

    impl TestWorld {
        fn new(positions: Vec<(f32, f32)>) -> Self {
            let n = positions.len();
            Self {
                positions_x: positions.iter().map(|p| p.0).collect(),
                positions_y: positions.iter().map(|p| p.1).collect(),
                alive: vec![true; n],
                sep_x: vec![0.0; n],
                sep_y: vec![0.0; n],
                neighbor_buf: Vec::new(),
            }
        }
    }

    impl EnemySeparation for TestWorld {
        fn enemy_count(&self) -> usize {
            self.positions_x.len()
        }
        fn is_alive(&self, i: usize) -> bool {
            self.alive[i]
        }
        fn pos_x(&self, i: usize) -> f32 {
            self.positions_x[i]
        }
        fn pos_y(&self, i: usize) -> f32 {
            self.positions_y[i]
        }
        fn add_pos_x(&mut self, i: usize, v: f32) {
            self.positions_x[i] += v;
        }
        fn add_pos_y(&mut self, i: usize, v: f32) {
            self.positions_y[i] += v;
        }
        fn sep_buf_x(&mut self) -> &mut Vec<f32> {
            &mut self.sep_x
        }
        fn sep_buf_y(&mut self) -> &mut Vec<f32> {
            &mut self.sep_y
        }
        fn neighbor_buf(&mut self) -> &mut Vec<usize> {
            &mut self.neighbor_buf
        }
    }

    #[test]
    fn overlapping_enemies_are_separated() {
        // 2 体が完全に同じ位置に重なっている
        let mut world = TestWorld::new(vec![(100.0, 100.0), (100.5, 100.5)]);
        let before_dist = {
            let dx = world.positions_x[0] - world.positions_x[1];
            let dy = world.positions_y[0] - world.positions_y[1];
            (dx * dx + dy * dy).sqrt()
        };

        apply_separation(&mut world, 30.0, 1.0, 0.016);

        let after_dist = {
            let dx = world.positions_x[0] - world.positions_x[1];
            let dy = world.positions_y[0] - world.positions_y[1];
            (dx * dx + dy * dy).sqrt()
        };

        assert!(
            after_dist > before_dist,
            "分離後の距離 ({after_dist:.3}) は分離前 ({before_dist:.3}) より大きいべき"
        );
    }

    #[test]
    fn well_separated_enemies_are_not_moved() {
        // 2 体が十分離れている（分離半径 30 より遠い）
        let mut world = TestWorld::new(vec![(0.0, 0.0), (100.0, 100.0)]);
        let before_x0 = world.positions_x[0];
        let before_y0 = world.positions_y[0];

        apply_separation(&mut world, 30.0, 1.0, 0.016);

        assert_eq!(
            world.positions_x[0], before_x0,
            "十分離れた敵は移動しないべき"
        );
        assert_eq!(
            world.positions_y[0], before_y0,
            "十分離れた敵は移動しないべき"
        );
    }

    #[test]
    fn dead_enemies_are_not_separated() {
        let mut world = TestWorld::new(vec![(100.0, 100.0), (100.5, 100.5)]);
        world.alive[1] = false;
        let before_x0 = world.positions_x[0];

        apply_separation(&mut world, 30.0, 1.0, 0.016);

        assert_eq!(
            world.positions_x[0], before_x0,
            "死亡した敵との分離は発生しないべき"
        );
    }

    #[test]
    fn single_enemy_no_panic() {
        let mut world = TestWorld::new(vec![(50.0, 50.0)]);
        // 1 体のみのとき apply_separation はパニックせず早期リターンするべき
        apply_separation(&mut world, 30.0, 1.0, 0.016);
    }
}
