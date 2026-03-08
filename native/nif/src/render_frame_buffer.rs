//! Path: native/nif/src/render_frame_buffer.rs
//! Summary: Elixir から push された RenderFrame を保持するスレッドセーフバッファ。
//!
//! Phase R-2: render_snapshot.rs を廃止し、Elixir 側（contents）が
//! DrawCommand リストを組み立てて push_render_frame NIF 経由でこのバッファに書き込む。
//! RenderBridge::next_frame() はこのバッファから RenderFrame を取得する。

use desktop_render::RenderFrame;
use std::sync::{Arc, RwLock};

/// Elixir から push された最新の RenderFrame を保持するバッファ。
///
/// `Arc<RwLock<RenderFrame>>` を薄くラップし、Rustler の `Resource` として
/// NIF 間で共有できるようにする。
pub struct RenderFrameBuffer(pub Arc<RwLock<RenderFrame>>);

impl Default for RenderFrameBuffer {
    fn default() -> Self {
        Self(Arc::new(RwLock::new(RenderFrame::default())))
    }
}

impl RenderFrameBuffer {
    pub fn new() -> Self {
        Self::default()
    }

    /// バッファの内容を新しい `RenderFrame` で置き換える。
    pub fn push(&self, frame: RenderFrame) {
        match self.0.write() {
            Ok(mut guard) => *guard = frame,
            Err(e) => {
                log::error!("RenderFrameBuffer: write lock poisoned: {e:?}");
                *e.into_inner() = frame;
            }
        }
    }

    /// バッファから現在の `RenderFrame` のクローンを取得する。
    pub fn get(&self) -> RenderFrame {
        match self.0.read() {
            Ok(guard) => guard.clone(),
            Err(e) => {
                log::error!("RenderFrameBuffer: read lock poisoned: {e:?}");
                e.into_inner().clone()
            }
        }
    }
}

impl rustler::Resource for RenderFrameBuffer {}
