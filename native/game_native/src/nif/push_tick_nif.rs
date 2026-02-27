//! Path: native/game_native/src/nif/push_tick_nif.rs
//! Summary: Push 型同期 NIF（push_tick / physics_result delta）
//!
//! 1.10.5: Elixir SSOT + Push 型同期の実装。
//! - `push_tick`: Elixir から入力・コマンドを受け取り、物理計算して delta を返す
//! - 全状態の転送ではなく、入力と制御コマンドのみを受け取る
//! - 返す delta は変化分のみ（全量ではない）

use super::util::lock_poisoned_err;
use crate::game_logic::run_physics_step_for_bench as physics_step_inner;
use crate::lock_metrics::record_write_wait;
use crate::world::GameWorld;
use rustler::{Atom, NifResult, ResourceArc};
use std::time::Instant;

use crate::ok;

/// push_tick: Elixir から入力を受け取り、物理計算して delta を返す
///
/// inputs: プレイヤー入力（dx, dy）
/// delta_ms: tick 間隔（ms）
#[rustler::nif(schedule = "DirtyCpu")]
pub fn push_tick(
    world: ResourceArc<GameWorld>,
    dx: f64,
    dy: f64,
    delta_ms: f64,
) -> NifResult<(Atom, u32, f64, f64, f64, u32, f64)> {
    let wait_start = Instant::now();
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    record_write_wait("nif.push_tick", wait_start.elapsed());

    // 入力を適用（inputs: プレイヤー移動方向）
    w.player.input_dx = dx as f32;
    w.player.input_dy = dy as f32;

    // 1.10.7: 補間用 - 前フレームの位置・タイムスタンプを保存
    w.prev_player_x = w.player.x;
    w.prev_player_y = w.player.y;
    w.prev_tick_ms = w.curr_tick_ms;

    // 物理計算を 1 tick 分実行
    let step_start = Instant::now();
    physics_step_inner(&mut w, delta_ms);
    let physics_ms = step_start.elapsed().as_secs_f64() * 1000.0;

    // 1.10.7: 補間用 - 現在フレームのタイムスタンプを更新
    w.curr_tick_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;

    // delta を返す（変化分のみ）
    let frame_id = w.frame_id;
    let player_x = w.player.x as f64;
    let player_y = w.player.y as f64;
    let player_hp = w.player.hp as f64;
    let enemy_count = w.enemies.positions_x.iter().zip(w.enemies.alive.iter())
        .filter(|(_, &alive)| alive)
        .count() as u32;

    Ok((ok(), frame_id, player_x, player_y, player_hp, enemy_count, physics_ms))
}
