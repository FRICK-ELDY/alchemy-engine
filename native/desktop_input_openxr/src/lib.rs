//! Path: native/desktop_input_openxr/src/lib.rs
//! Summary: OpenXR 入力ブリッジ（VR デバイス）
//!
//! 以下のイベントを nif 経由で Elixir に送信する:
//! - `{:head_pose, data}` — ヘッドセットの位置・姿勢
//! - `{:controller_pose, data}` — コントローラーの位置・姿勢
//! - `{:controller_button, data}` — コントローラーボタン
//! - `{:tracker_pose, data}` — トラッカーの位置・姿勢

/// XR 入力ループを実行する。
/// `on_event` が各イベントごとに呼ばれる。nif が Elixir へエンコード・送信する。
///
/// VR ランタイムが利用できない場合は即座に戻る。
/// `openxr` フィーチャー有効時は OpenXR セッションを試行する。
#[cfg_attr(not(feature = "openxr"), allow(unused_variables, unused_mut))]
pub fn run_xr_input_loop<F>(mut on_event: F)
where
    F: FnMut(XrInputEvent) + Send + 'static,
{
    #[cfg(feature = "openxr")]
    {
        if let Err(e) = run_openxr_loop(&mut on_event) {
            log::warn!("OpenXR input loop failed: {e} — VR input disabled");
        }
        return;
    }

    #[cfg(not(feature = "openxr"))]
    {
        log::debug!("OpenXR feature disabled — VR input unavailable");
    }
}

#[cfg(feature = "openxr")]
fn run_openxr_loop<F>(_on_event: &mut F) -> Result<(), String>
where
    F: FnMut(XrInputEvent),
{
    // TODO: OpenXR インスタンス・ヘッドレスセッション作成
    // xrLocateSpace で head/controller pose 取得
    // ポーリングループで on_event を呼ぶ
    Err("OpenXR integration not yet implemented".to_string())
}

/// OpenXR 入力ソースのトレイト。
/// Elixir へのイベント送信は nif が担う。
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
