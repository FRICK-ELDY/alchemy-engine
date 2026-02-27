//! Path: native/game_core/src/physics/spatial_hash.rs
//! Summary: 空間ハッシュによる衝突検出・近傍クエリ

use rustc_hash::FxHashMap;

pub struct SpatialHash {
    pub cell_size: f32,
    cells: FxHashMap<(i32, i32), Vec<usize>>,
}

impl SpatialHash {
    pub fn new(cell_size: f32) -> Self {
        Self {
            cell_size,
            cells: FxHashMap::default(),
        }
    }

    pub fn clear(&mut self) {
        self.cells.clear();
    }

    pub fn insert(&mut self, id: usize, x: f32, y: f32) {
        let key = self.cell_key(x, y);
        self.cells.entry(key).or_default().push(id);
    }

    fn cell_key(&self, x: f32, y: f32) -> (i32, i32) {
        (
            (x / self.cell_size).floor() as i32,
            (y / self.cell_size).floor() as i32,
        )
    }

    /// 指定円の範囲内にあるエンティティ ID を `buf` に書き込む（アロケーションなし）。
    /// 呼び出し前に `buf` をクリアする必要はない（内部で `clear()` する）。
    pub fn query_nearby_into(&self, x: f32, y: f32, radius: f32, buf: &mut Vec<usize>) {
        buf.clear();
        let r = (radius / self.cell_size).ceil() as i32;
        let cx = (x / self.cell_size).floor() as i32;
        let cy = (y / self.cell_size).floor() as i32;
        for ix in (cx - r)..=(cx + r) {
            for iy in (cy - r)..=(cy + r) {
                if let Some(ids) = self.cells.get(&(ix, iy)) {
                    buf.extend_from_slice(ids);
                }
            }
        }
    }

    /// 後方互換用（`query_nearby_into` への移行が完了したら削除可）
    pub fn query_nearby(&self, x: f32, y: f32, radius: f32) -> Vec<usize> {
        let mut buf = Vec::new();
        self.query_nearby_into(x, y, radius, &mut buf);
        buf
    }
}

#[derive(Clone, Copy, Debug)]
pub struct StaticObstacle {
    pub x:      f32,
    pub y:      f32,
    pub radius: f32,
    pub kind:   u8,
}

pub struct CollisionWorld {
    pub dynamic:     SpatialHash,
    pub static_hash: SpatialHash,
    pub obstacles:   Vec<StaticObstacle>,
}

impl CollisionWorld {
    pub fn new(cell_size: f32) -> Self {
        Self {
            dynamic:     SpatialHash::new(cell_size),
            static_hash: SpatialHash::new(cell_size),
            obstacles:   Vec::new(),
        }
    }

    pub fn rebuild_static(&mut self, obstacles: &[(f32, f32, f32, u8)]) {
        self.obstacles.clear();
        self.static_hash.clear();
        for (x, y, radius, kind) in obstacles {
            let idx = self.obstacles.len();
            self.obstacles.push(StaticObstacle {
                x: *x, y: *y, radius: *radius, kind: *kind,
            });
            self.static_hash.insert(idx, *x, *y);
        }
    }

    pub fn query_static_nearby_into(
        &self,
        x: f32, y: f32, radius: f32,
        buf: &mut Vec<usize>,
    ) {
        self.static_hash.query_nearby_into(x, y, radius + 80.0, buf);
        let obstacles = &self.obstacles;
        buf.retain(|&idx| {
            if let Some(o) = obstacles.get(idx) {
                let hit_r = radius + o.radius;
                let dx = x - o.x;
                let dy = y - o.y;
                dx * dx + dy * dy <= hit_r * hit_r
            } else {
                false
            }
        });
    }
}
