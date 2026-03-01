//! Path: native/game_physics/src/world/bullet.rs
//! Summary: 蠑ｾ荳ｸ SoA・・ulletWorld・峨→謠冗判遞ｮ蛻･螳壽焚

/// 蠑ｾ荳ｸ縺ｮ謠冗判遞ｮ蛻･・・enderer 縺ｫ貂｡縺・kind 蛟､・・
pub const BULLET_KIND_NORMAL:    u8 = 4;  // MagicWand / Axe / Cross・磯ｻ・牡縺・・・・
pub const BULLET_KIND_FIREBALL:  u8 = 8;  // Fireball・郁ｵ､讖吶・轤守帥・・
pub const BULLET_KIND_LIGHTNING: u8 = 9;  // Lightning・域ｰｴ濶ｲ縺ｮ髮ｻ謦・帥・・
pub const BULLET_KIND_WHIP:      u8 = 10; // Whip・磯ｻ・ｷ代・蠑ｧ迥ｶ・・
// 11=SlimeKing, 12=BatLord, 13=StoneGolem・医・繧ｹ render_kind 縺ｨ蜈ｱ譛会ｼ・
pub const BULLET_KIND_ROCK:      u8 = 14; // StoneGolem 縺ｮ蟯ｩ蠑ｾ

/// 蠑ｾ荳ｸ SoA・・tructure of Arrays・・
pub struct BulletWorld {
    pub positions_x:  Vec<f32>,
    pub positions_y:  Vec<f32>,
    pub velocities_x: Vec<f32>,
    pub velocities_y: Vec<f32>,
    pub damage:       Vec<i32>,
    pub lifetime:     Vec<f32>,
    pub alive:        Vec<bool>,
    /// true 縺ｮ蠑ｾ荳ｸ縺ｯ謨ｵ縺ｫ蠖薙◆縺｣縺ｦ繧よｶ医∴縺壹↓雋ｫ騾壹☆繧具ｼ・ireball 逕ｨ・・
    pub piercing:     Vec<bool>,
    /// 謠冗判遞ｮ蛻･・・ULLET_KIND_* 螳壽焚・・
    pub render_kind:  Vec<u8>,
    pub count:        usize,
    /// 遨ｺ縺阪せ繝ｭ繝・ヨ縺ｮ繧､繝ｳ繝・ャ繧ｯ繧ｹ繧ｹ繧ｿ繝・け 窶・O(1) 縺ｧ繧ｹ繝ｭ繝・ヨ繧貞叙蠕励・霑泌唆
    free_list:        Vec<usize>,
}

impl BulletWorld {
    pub fn new() -> Self {
        Self {
            positions_x:  Vec::new(),
            positions_y:  Vec::new(),
            velocities_x: Vec::new(),
            velocities_y: Vec::new(),
            damage:       Vec::new(),
            lifetime:     Vec::new(),
            alive:        Vec::new(),
            piercing:     Vec::new(),
            render_kind:  Vec::new(),
            count:        0,
            free_list:    Vec::new(),
        }
    }

    pub fn spawn(&mut self, x: f32, y: f32, vx: f32, vy: f32, damage: i32, lifetime: f32) {
        self.spawn_ex(x, y, vx, vy, damage, lifetime, false, BULLET_KIND_NORMAL);
    }

    pub fn spawn_piercing(&mut self, x: f32, y: f32, vx: f32, vy: f32, damage: i32, lifetime: f32) {
        self.spawn_ex(x, y, vx, vy, damage, lifetime, true, BULLET_KIND_FIREBALL);
    }

    /// 繝繝｡繝ｼ繧ｸ 0繝ｻ遏ｭ蜻ｽ縺ｮ陦ｨ遉ｺ蟆ら畑繧ｨ繝輔ぉ繧ｯ繝亥ｼｾ繧堤函謌舌☆繧具ｼ・hip / Lightning 逕ｨ・・
    pub fn spawn_effect(&mut self, x: f32, y: f32, lifetime: f32, render_kind: u8) {
        self.spawn_ex(x, y, 0.0, 0.0, 0, lifetime, false, render_kind);
    }

    pub fn spawn_ex(&mut self, x: f32, y: f32, vx: f32, vy: f32, damage: i32, lifetime: f32, piercing: bool, render_kind: u8) {
        if let Some(i) = self.free_list.pop() {
            self.positions_x[i]  = x;
            self.positions_y[i]  = y;
            self.velocities_x[i] = vx;
            self.velocities_y[i] = vy;
            self.damage[i]       = damage;
            self.lifetime[i]     = lifetime;
            self.alive[i]        = true;
            self.piercing[i]     = piercing;
            self.render_kind[i]  = render_kind;
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
}
