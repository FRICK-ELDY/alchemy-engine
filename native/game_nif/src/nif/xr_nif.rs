//! Path: native/game_nif/src/nif/xr_nif.rs
//! Summary: XR 入力スレッド起動 NIF
//!
//! Elixir から VR 入力を有効にする際に呼ぶ。
//! input_openxr のループを別スレッドで実行し、イベントを GameEvents に送信する。

use crate::xr_bridge::run_xr_input_thread;
use rustler::{Atom, LocalPid, NifResult};

#[rustler::nif]
pub fn spawn_xr_input_thread(pid: LocalPid) -> NifResult<Atom> {
    run_xr_input_thread(pid);
    Ok(crate::ok())
}
