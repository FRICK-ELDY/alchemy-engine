//! Rustler NIF クレート — **Formula VM のみ**（`run_formula_bytecode/3`）。
//!
//! ゲーム ECS・物理・protobuf インジェクション等はフェーズ 4 で削除した。
//! 復旧が必要な場合は Git 履歴の `native/nif/src/physics` 等を参照する。

mod formula;
mod nif;

pub use nif::load;

#[cfg(feature = "umbrella")]
rustler::init!("Elixir.Core.NifBridge", load = nif::load);

#[cfg(not(feature = "umbrella"))]
rustler::init!("Elixir.App.NifBridge", load = nif::load);
