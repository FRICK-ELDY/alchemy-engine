//! Path: native/game_physics/src/world/particle.rs
//! Summary: パーティクル SoA（ParticleWorld）

use crate::physics::rng::SimpleRng;

/// パーティクル SoA（Structure of Arrays）
pub struct ParticleWorld {
    pub positions_x:  Vec<f32>,
    pub positions_y:  Vec<f32>,
    pub velocities_x: Vec<f32>,
    pub velocities_y: Vec<f32>,
    pub lifetime:     Vec<f32>,
    pub max_lifetime: Vec<f32>,
    pub color:        Vec<[f32; 4]>,
    pub size:         Vec<f32>,
    pub alive:        Vec<bool>,
    pub count:        usize,
    rng:              SimpleRng,
    /// 空きスロットのインデックススタック — O(1) でスロットを取得・返却
    free_list:        Vec<usize>,
}

impl ParticleWorld {
    pub fn new(seed: u64) -> Self {
        Self {
            positions_x:  Vec::new(),
            positions_y:  Vec::new(),
            velocities_x: Vec::new(),
            velocities_y: Vec::new(),
            lifetime:     Vec::new(),
            max_lifetime: Vec::new(),
            color:        Vec::new(),
            size:         Vec::new(),
            alive:        Vec::new(),
            count:        0,
            rng:          SimpleRng::new(seed),
            free_list:    Vec::new(),
        }
    }

    pub fn len(&self) -> usize {
        self.positions_x.len()
    }

    pub fn spawn_one(
        &mut self,
        x: f32, y: f32,
        vx: f32, vy: f32,
        lifetime: f32,
        color: [f32; 4],
        size: f32,
    ) {
        if let Some(i) = self.free_list.pop() {
            self.positions_x[i]  = x;
            self.positions_y[i]  = y;
            self.velocities_x[i] = vx;
            self.velocities_y[i] = vy;
            self.lifetime[i]     = lifetime;
            self.max_lifetime[i] = lifetime;
            self.color[i]        = color;
            self.size[i]         = size;
            self.alive[i]        = true;
        } else {
            self.positions_x.push(x);
            self.positions_y.push(y);
            self.velocities_x.push(vx);
            self.velocities_y.push(vy);
            self.lifetime.push(lifetime);
            self.max_lifetime.push(lifetime);
            self.color.push(color);
            self.size.push(size);
            self.alive.push(true);
        }
        self.count += 1;
    }

    pub fn emit(&mut self, x: f32, y: f32, count: usize, color: [f32; 4]) {
        for _ in 0..count {
            let angle = self.rng.next_f32() * std::f32::consts::TAU;
            let speed = 50.0 + self.rng.next_f32() * 150.0;
            let vx = angle.cos() * speed;
            let vy = angle.sin() * speed;
            let lifetime = 0.3 + self.rng.next_f32() * 0.4;
            let size = 4.0 + self.rng.next_f32() * 4.0;
            self.spawn_one(x, y, vx, vy, lifetime, color, size);
        }
    }

    pub fn kill(&mut self, i: usize) {
        if self.alive[i] {
            self.alive[i] = false;
            self.count = self.count.saturating_sub(1);
            self.free_list.push(i);
        }
    }
}
