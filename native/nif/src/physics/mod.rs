//! physics: ECS World・ゲームロジック・物理演算・Dead Reckoning
//! （ヘッドレス動作可能 — rustler 等の NIF 依存なし）

pub mod boss;
pub mod constants;
pub mod enemy;
pub mod entity_params;
pub mod item;
#[allow(clippy::module_inception)]
pub mod physics;
pub mod util;
pub mod weapon;

pub mod game_logic;
pub mod world;
