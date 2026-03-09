//! Win / Mac / Linux 向け rodio 音声出力
//!
//! CoreAudio (macOS) / WASAPI (Windows) / ALSA (Linux)

use rodio::{OutputStream, OutputStreamBuilder};

/// デフォルトの音声出力ストリームを開く。
///
/// 失敗時は None（デバイス未検出・権限不足等）。
pub fn open_default_stream() -> Option<OutputStream> {
    OutputStreamBuilder::open_default_stream().ok()
}
