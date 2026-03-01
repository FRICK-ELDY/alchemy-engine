//! game_physics: ECS World・物理演算（衝突・分離・空間ハッシュ・Chase AI）
//! （ヘッドレス動作可能 — rustler 等の NIF 依存なし）
//!
//! 補間（Dead Reckoning / フレーム間 lerp）はこのクレートの責務ではない。
//! Elixir 20-30Hz と描画 60-144Hz の差を埋める補間処理は game_nif/render_snapshot に属する。

pub mod boss;
pub mod constants;
pub mod entity_params;
pub mod enemy;
pub mod item;
pub mod physics;
pub mod util;
pub mod weapon;

pub mod world;
pub mod game_logic;
