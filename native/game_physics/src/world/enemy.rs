//! Path: native/game_physics/src/world/enemy.rs
//! Summary: 謨ｵ SoA・・nemyWorld・峨→ EnemySeparation 縺ｮ螳溯｣・

use crate::entity_params::EnemyParams;
use crate::physics::separation::EnemySeparation;

/// 謨ｵ SoA・・tructure of Arrays・・
#[derive(Clone)]
pub struct EnemyWorld {
    pub positions_x:  Vec<f32>,
    pub positions_y:  Vec<f32>,
    pub velocities_x: Vec<f32>,
    pub velocities_y: Vec<f32>,
    pub speeds:       Vec<f32>,
    pub hp:           Vec<f32>,
    /// 逕溷ｭ倥ヵ繝ｩ繧ｰ: 0xFF = 逕溷ｭ・ 0x00 = 豁ｻ莠｡・・IMD 繝槭せ繧ｯ縺ｨ縺励※逶ｴ謗･繝ｭ繝ｼ繝牙庄閭ｽ・・
    pub alive:        Vec<u8>,
    pub kind_ids:     Vec<u8>,
    pub count:        usize,
    /// 蛻・屬繝代せ逕ｨ縺ｮ菴懈･ｭ繝舌ャ繝輔ぃ・域ｯ弱ヵ繝ｬ繝ｼ繝蜀榊茜逕ｨ縺励※繧｢繝ｭ繧ｱ繝ｼ繧ｷ繝ｧ繝ｳ繧貞屓驕ｿ・・
    pub sep_x:        Vec<f32>,
    pub sep_y:        Vec<f32>,
    /// 霑鷹團繧ｯ繧ｨ繝ｪ邨先棡縺ｮ蜀榊茜逕ｨ繝舌ャ繝輔ぃ・域ｯ弱ヵ繝ｬ繝ｼ繝縺ｮ繝偵・繝励い繝ｭ繧ｱ繝ｼ繧ｷ繝ｧ繝ｳ繧貞屓驕ｿ・・
    pub neighbor_buf: Vec<usize>,
    /// 遨ｺ縺阪せ繝ｭ繝・ヨ縺ｮ繧､繝ｳ繝・ャ繧ｯ繧ｹ繧ｹ繧ｿ繝・け 窶・O(1) 縺ｧ繧ｹ繝ｭ繝・ヨ繧貞叙蠕励・霑泌唆
    free_list:        Vec<usize>,
}

impl EnemyWorld {
    pub fn new() -> Self {
        Self {
            positions_x:  Vec::new(),
            positions_y:  Vec::new(),
            velocities_x: Vec::new(),
            velocities_y: Vec::new(),
            speeds:       Vec::new(),
            hp:           Vec::new(),
            alive:        Vec::new(),
            kind_ids:     Vec::new(),
            count:        0,
            sep_x:        Vec::new(),
            sep_y:        Vec::new(),
            neighbor_buf: Vec::new(),
            free_list:    Vec::new(),
        }
    }

    pub fn len(&self) -> usize {
        self.positions_x.len()
    }

    pub fn kill(&mut self, i: usize) {
        if self.alive[i] != 0 {
            self.alive[i] = 0x00;
            self.count = self.count.saturating_sub(1);
            self.free_list.push(i);
        }
    }

    /// 謖・ｮ・ID 縺ｮ謨ｵ繧・`positions` 縺ｮ蠎ｧ讓吶↓繧ｹ繝昴・繝ｳ・・(1) 縺ｧ繧ｹ繝ｭ繝・ヨ蜿門ｾ暦ｼ・
    /// `ep` 縺ｯ蜻ｼ縺ｳ蜃ｺ縺怜・縺ｧ `params.get_enemy(kind_id).clone()` 縺励※貂｡縺吶・
    /// ・亥庄螟牙溽畑縺ｨ荳榊､牙溽畑縺ｮ遶ｶ蜷医ｒ驕ｿ縺代ｋ縺溘ａ縲√ユ繝ｼ繝悶Ν縺ｧ縺ｯ縺ｪ縺丞､繧貞女縺大叙繧具ｼ・
    pub fn spawn(&mut self, positions: &[(f32, f32)], kind_id: u8, ep: &EnemyParams) {
        let speed  = ep.speed;
        let max_hp = ep.max_hp;

        for &(x, y) in positions {
            if let Some(i) = self.free_list.pop() {
                self.positions_x[i]  = x;
                self.positions_y[i]  = y;
                self.velocities_x[i] = 0.0;
                self.velocities_y[i] = 0.0;
                self.speeds[i]       = speed;
                self.hp[i]           = max_hp;
                self.alive[i]        = 0xFF;
                self.kind_ids[i]     = kind_id;
                self.sep_x[i]        = 0.0;
                self.sep_y[i]        = 0.0;
            } else {
                self.positions_x.push(x);
                self.positions_y.push(y);
                self.velocities_x.push(0.0);
                self.velocities_y.push(0.0);
                self.speeds.push(speed);
                self.hp.push(max_hp);
                self.alive.push(0xFF);
                self.kind_ids.push(kind_id);
                self.sep_x.push(0.0);
                self.sep_y.push(0.0);
            }
            self.count += 1;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entity_params::EnemyParams;

    fn default_params() -> EnemyParams {
        EnemyParams {
            max_hp:           50.0,
            speed:            80.0,
            radius:           20.0,
            damage_per_sec:   10.0,
            render_kind:      1,
            particle_color:   [1.0, 0.5, 0.0, 1.0],
            passes_obstacles: false,
        }
    }

    #[test]
    fn spawn_increases_count() {
        let mut world = EnemyWorld::new();
        let ep = default_params();
        world.spawn(&[(0.0, 0.0), (10.0, 10.0)], 0, &ep);
        assert_eq!(world.count, 2);
        assert_eq!(world.len(), 2);
    }

    #[test]
    fn kill_decreases_count_and_adds_to_free_list() {
        let mut world = EnemyWorld::new();
        let ep = default_params();
        world.spawn(&[(0.0, 0.0), (10.0, 10.0)], 0, &ep);

        world.kill(0);

        assert_eq!(world.count, 1, "kill 蠕後・ count 縺ｯ 1 縺ｧ縺ゅｋ縺ｹ縺・);
        assert_eq!(world.alive[0], 0x00, "kill 蠕後・ alive=0x00 縺ｧ縺ゅｋ縺ｹ縺・);
    }

    #[test]
    fn spawn_reuses_free_list_slot() {
        let mut world = EnemyWorld::new();
        let ep = default_params();
        world.spawn(&[(0.0, 0.0)], 0, &ep);
        world.kill(0);

        let len_before = world.len();
        world.spawn(&[(99.0, 99.0)], 0, &ep);

        // free_list 縺ｮ繧ｹ繝ｭ繝・ヨ繧貞・蛻ｩ逕ｨ縺吶ｋ縺溘ａ驟榊・髟ｷ縺ｯ螟峨ｏ繧峨↑縺・
        assert_eq!(
            world.len(),
            len_before,
            "free_list 蜀榊茜逕ｨ譎ゅ・驟榊・縺御ｼｸ髟ｷ縺励↑縺・∋縺・
        );
        assert_eq!(world.count, 1);
        assert_ne!(world.alive[0], 0x00);
        assert!((world.positions_x[0] - 99.0).abs() < 0.001);
    }

    #[test]
    fn kill_idempotent() {
        let mut world = EnemyWorld::new();
        let ep = default_params();
        world.spawn(&[(0.0, 0.0)], 0, &ep);
        world.kill(0);
        world.kill(0); // 2 蝗・kill 縺励※繧・count 縺瑚ｲ縺ｫ縺ｪ繧峨↑縺・
        assert_eq!(world.count, 0);
    }

    #[test]
    fn spawn_sets_correct_kind_id() {
        let mut world = EnemyWorld::new();
        let ep = default_params();
        world.spawn(&[(0.0, 0.0)], 3, &ep);
        assert_eq!(world.kind_ids[0], 3);
    }
}

impl EnemySeparation for EnemyWorld {
    fn enemy_count(&self) -> usize          { self.positions_x.len() }
    fn is_alive(&self, i: usize) -> bool    { self.alive[i] != 0 }
    fn pos_x(&self, i: usize) -> f32        { self.positions_x[i] }
    fn pos_y(&self, i: usize) -> f32        { self.positions_y[i] }
    fn add_pos_x(&mut self, i: usize, v: f32) { self.positions_x[i] += v; }
    fn add_pos_y(&mut self, i: usize, v: f32) { self.positions_y[i] += v; }
    fn sep_buf_x(&mut self) -> &mut Vec<f32>  { &mut self.sep_x }
    fn sep_buf_y(&mut self) -> &mut Vec<f32>  { &mut self.sep_y }
    fn neighbor_buf(&mut self) -> &mut Vec<usize> { &mut self.neighbor_buf }
}
