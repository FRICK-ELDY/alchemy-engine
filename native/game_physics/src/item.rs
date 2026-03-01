//! Path: native/game_core/src/item.rs
//! Summary: アイテム種類・レンダー kind の定義と ItemWorld

/// アイテムの種類
#[derive(Clone, Copy, PartialEq, Debug, Default)]
#[repr(u8)]
pub enum ItemKind {
    #[default]
    Gem = 0, // 経験値宝石（緑）
    Potion = 1, // 回復ポーション（赤）
    Magnet = 2, // 磁石（黄）
}

/// `get_render_data` / `get_item_data` が返す kind 値
pub const RENDER_KIND_GEM: u8 = 5;
pub const RENDER_KIND_POTION: u8 = 6;
pub const RENDER_KIND_MAGNET: u8 = 7;

impl ItemKind {
    /// レンダラーに渡す kind 値
    pub fn render_kind(self) -> u8 {
        match self {
            Self::Gem => RENDER_KIND_GEM,
            Self::Potion => RENDER_KIND_POTION,
            Self::Magnet => RENDER_KIND_MAGNET,
        }
    }
}

/// アイテム SoA（Structure of Arrays）
///
/// フリーリストにより kill されたスロットを O(1) で再利用する。
pub struct ItemWorld {
    pub positions_x: Vec<f32>,
    pub positions_y: Vec<f32>,
    pub kinds: Vec<ItemKind>,
    pub value: Vec<u32>, // Gem: EXP 量, Potion: 回復量, Magnet: 未使用
    pub alive: Vec<bool>,
    pub count: usize,
    /// kill 時にインデックスを積み、spawn 時に pop して再利用する
    free_list: Vec<usize>,
}

impl ItemWorld {
    pub fn new() -> Self {
        Self {
            positions_x: Vec::new(),
            positions_y: Vec::new(),
            kinds: Vec::new(),
            value: Vec::new(),
            alive: Vec::new(),
            count: 0,
            free_list: Vec::new(),
        }
    }

    pub fn len(&self) -> usize {
        self.positions_x.len()
    }

    /// アイテムをスポーンする。空きスロットがあれば O(1) で再利用する。
    pub fn spawn(&mut self, x: f32, y: f32, kind: ItemKind, value: u32) {
        if let Some(i) = self.free_list.pop() {
            self.positions_x[i] = x;
            self.positions_y[i] = y;
            self.kinds[i] = kind;
            self.value[i] = value;
            self.alive[i] = true;
        } else {
            self.positions_x.push(x);
            self.positions_y.push(y);
            self.kinds.push(kind);
            self.value.push(value);
            self.alive.push(true);
        }
        self.count += 1;
    }

    /// アイテムを消去し、スロットをフリーリストに返却する。
    pub fn kill(&mut self, i: usize) {
        if self.alive[i] {
            self.alive[i] = false;
            self.count = self.count.saturating_sub(1);
            self.free_list.push(i);
        }
    }
}
