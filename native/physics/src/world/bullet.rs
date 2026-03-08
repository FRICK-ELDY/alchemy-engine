//! Path: native/physics/src/world/bullet.rs
//! Summary: 弾丸 SoA（BulletWorld）と描画種別定数

/// 弾丸の描画種別（renderer に渡す kind 値）
pub const BULLET_KIND_NORMAL: u8 = 4; // MagicWand / Axe / Cross（黄色い円）
pub const BULLET_KIND_FIREBALL: u8 = 8; // Fireball（赤橙の炎球）
pub const BULLET_KIND_LIGHTNING: u8 = 9; // Lightning（水色の電撃球）
pub const BULLET_KIND_WHIP: u8 = 10; // Whip（黄緑の弧状）
                                     // 11=SlimeKing, 12=BatLord, 13=StoneGolem（ボス render_kind と共有）
pub const BULLET_KIND_ROCK: u8 = 14; // StoneGolem の岩弾

/// 弾丸 SoA（Structure of Arrays）
pub struct BulletWorld {
    pub positions_x: Vec<f32>,
    pub positions_y: Vec<f32>,
    pub velocities_x: Vec<f32>,
    pub velocities_y: Vec<f32>,
    pub damage: Vec<i32>,
    pub lifetime: Vec<f32>,
    pub alive: Vec<bool>,
    /// true の弾丸は敵に当たっても消えずに貫通する（Fireball 用）
    pub piercing: Vec<bool>,
    /// 描画種別（BULLET_KIND_* 定数）
    pub render_kind: Vec<u8>,
    /// P2-1: ヒット時パーティクル色 [r, g, b, a]。contents から weapon_params 経由で注入。
    pub hit_particle_color: Vec<[f32; 4]>,
    pub count: usize,
    /// 空きスロットのインデックススタック — O(1) でスロットを取得・返却
    free_list: Vec<usize>,
}

impl Default for BulletWorld {
    fn default() -> Self {
        Self::new()
    }
}

/// 弾丸ヒット時のデフォルトパーティクル色（action_nif 等で spawn_ex 直接呼び出し時）
pub const DEFAULT_BULLET_HIT_COLOR: [f32; 4] = [1.0, 0.9, 0.3, 1.0];
/// 貫通弾ヒット時のデフォルトパーティクル色
pub const DEFAULT_PIERCING_HIT_COLOR: [f32; 4] = [1.0, 0.4, 0.0, 1.0];

impl BulletWorld {
    pub fn new() -> Self {
        Self {
            positions_x: Vec::new(),
            positions_y: Vec::new(),
            velocities_x: Vec::new(),
            velocities_y: Vec::new(),
            damage: Vec::new(),
            lifetime: Vec::new(),
            alive: Vec::new(),
            piercing: Vec::new(),
            render_kind: Vec::new(),
            hit_particle_color: Vec::new(),
            count: 0,
            free_list: Vec::new(),
        }
    }

    pub fn spawn(&mut self, x: f32, y: f32, vx: f32, vy: f32, damage: i32, lifetime: f32) {
        self.spawn_with_hit_color(
            x,
            y,
            vx,
            vy,
            damage,
            lifetime,
            false,
            BULLET_KIND_NORMAL,
            DEFAULT_BULLET_HIT_COLOR,
        );
    }

    pub fn spawn_piercing(&mut self, x: f32, y: f32, vx: f32, vy: f32, damage: i32, lifetime: f32) {
        self.spawn_with_hit_color(
            x,
            y,
            vx,
            vy,
            damage,
            lifetime,
            true,
            BULLET_KIND_FIREBALL,
            DEFAULT_PIERCING_HIT_COLOR,
        );
    }

    /// ヒット色を指定して弾丸を生成（P2-1: weapon_params.hit_particle_color から渡す）
    #[allow(clippy::too_many_arguments)]
    pub fn spawn_with_hit_color(
        &mut self,
        x: f32,
        y: f32,
        vx: f32,
        vy: f32,
        damage: i32,
        lifetime: f32,
        piercing: bool,
        render_kind: u8,
        hit_color: [f32; 4],
    ) {
        self.spawn_ex(
            x,
            y,
            vx,
            vy,
            damage,
            lifetime,
            piercing,
            render_kind,
            hit_color,
        );
    }

    /// ダメージ 0・短命の表示専用エフェクト弾を生成する（Whip / Lightning 用）
    pub fn spawn_effect(&mut self, x: f32, y: f32, lifetime: f32, render_kind: u8) {
        self.spawn_ex(
            x,
            y,
            0.0,
            0.0,
            0,
            lifetime,
            false,
            render_kind,
            DEFAULT_BULLET_HIT_COLOR,
        );
    }

    #[allow(clippy::too_many_arguments)]
    pub fn spawn_ex(
        &mut self,
        x: f32,
        y: f32,
        vx: f32,
        vy: f32,
        damage: i32,
        lifetime: f32,
        piercing: bool,
        render_kind: u8,
        hit_particle_color: [f32; 4],
    ) {
        if let Some(i) = self.free_list.pop() {
            self.positions_x[i] = x;
            self.positions_y[i] = y;
            self.velocities_x[i] = vx;
            self.velocities_y[i] = vy;
            self.damage[i] = damage;
            self.lifetime[i] = lifetime;
            self.alive[i] = true;
            self.piercing[i] = piercing;
            self.render_kind[i] = render_kind;
            self.hit_particle_color[i] = hit_particle_color;
        } else {
            self.positions_x.push(x);
            self.positions_y.push(y);
            self.velocities_x.push(vx);
            self.velocities_y.push(vy);
            self.damage.push(damage);
            self.lifetime.push(lifetime);
            self.alive.push(true);
            self.piercing.push(piercing);
            self.render_kind.push(render_kind);
            self.hit_particle_color.push(hit_particle_color);
        }
        self.count += 1;
    }

    pub fn kill(&mut self, i: usize) {
        if self.alive[i] {
            self.alive[i] = false;
            self.count = self.count.saturating_sub(1);
            self.free_list.push(i);
        }
    }

    pub fn len(&self) -> usize {
        self.positions_x.len()
    }

    pub fn is_empty(&self) -> bool {
        self.positions_x.is_empty()
    }
}
