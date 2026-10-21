//! XR層（The Shell for VR）
//!
//! OpenXR セッションと入力管理。
//! app が使用し、VR 入力は network 経由で Elixir へ送信する。
//!
//! 以下のイベントを送信:
//! - `{:head_pose, data}` — ヘッドセットの位置・姿勢
//! - `{:controller_pose, data}` — コントローラーの位置・姿勢
//! - `{:controller_button, data}` — コントローラーボタン
//! - `{:tracker_pose, data}` — トラッカーの位置・姿勢

pub mod common;
pub(crate) mod platform;

#[cfg(feature = "openxr")]
mod openxr_loop;

/// XR 入力ループを実行する。
/// `on_event` が各イベントごとに呼ばれる。app が network 経由で Elixir へ送信する。
///
/// VR ランタイムが利用できない場合は即座に戻る。
/// `openxr` フィーチャー有効時は OpenXR セッション（`XR_MND_headless`）を試行する。
#[cfg_attr(not(feature = "openxr"), allow(unused_variables, unused_mut))]
pub fn run_xr_input_loop<F>(mut on_event: F)
where
    F: FnMut(XrInputEvent) + Send + 'static,
{
    #[cfg(feature = "openxr")]
    {
        if let Err(e) = openxr_loop::run_openxr_loop(&mut on_event) {
            log::warn!("OpenXR input loop failed: {e} — VR input disabled");
        }
    }

    #[cfg(not(feature = "openxr"))]
    {
        log::debug!("OpenXR feature disabled — VR input unavailable");
    }
}

/// OpenXR 入力ソースのトレイト。
/// イベント送信は app が network 経由で行う。
pub trait XrInputSource: Send + 'static {
    /// ポーリングして新しいイベントを取得する。
    /// 実装時に OpenXR セッションから head pose, controller 等を読み取る。
    fn poll(&mut self) -> Vec<XrInputEvent> {
        let _ = self;
        vec![]
    }
}

/// OpenXR 由来の入力イベント。
#[derive(Debug, Clone)]
pub enum XrInputEvent {
    /// ヘッドセットの位置・姿勢
    HeadPose {
        position: [f32; 3],
        orientation: [f32; 4],
        timestamp_us: u64,
    },
    /// コントローラーの位置・姿勢
    ControllerPose {
        hand: Hand,
        position: [f32; 3],
        orientation: [f32; 4],
        timestamp_us: u64,
    },
    /// コントローラーボタン
    ControllerButton {
        hand: Hand,
        button: ControllerButton,
        pressed: bool,
    },
    /// トラッカーの位置・姿勢
    TrackerPose {
        tracker_id: u32,
        position: [f32; 3],
        orientation: [f32; 4],
        velocity: Option<[f32; 3]>,
        timestamp_us: u64,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hand {
    Left,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ControllerButton {
    Trigger,
    Grip,
    Thumbstick,
    A,
    B,
    X,
    Y,
    Menu,
    System,
}
