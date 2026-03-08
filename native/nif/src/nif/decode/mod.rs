//! Path: native/nif/src/nif/decode/mod.rs
//! Summary: MessagePack デコードヘルパー
//!
//! - `msgpack_injection`: set_frame_injection_binary 用。GameWorldInner 注入（player_input 等）。
//!   RenderFrame とは独立。world_nif からのみ使用。
//! - RenderFrame デコード（camera, draw_command, ui_canvas, decode_cursor_grab 等）は Phase 2 で削除済み。

mod msgpack_injection;

pub use msgpack_injection::apply_injection_from_msgpack;
