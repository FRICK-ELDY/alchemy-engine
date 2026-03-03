//! Path: native/game_input_openxr/src/lib.rs
//! Summary: OpenXR 入力ブリッジ（VR デバイス）
//!
//! Phase 3 で実装予定。以下のイベントを Elixir に送信する:
//! - `{:head_pose, data}` — ヘッドセットの位置・姿勢
//! - `{:controller_pose, data}` — コントローラーの位置・姿勢
//! - `{:controller_button, data}` — コントローラーボタン
//! - `{:hand_pose, data}` — ハンドトラッキング（オプション）
//! - `{:tracker_pose, data}` — トラッカーの位置・姿勢

/// OpenXR 入力ソースのトレイト。
/// Elixir へのイベント送信は game_nif が担う。
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
