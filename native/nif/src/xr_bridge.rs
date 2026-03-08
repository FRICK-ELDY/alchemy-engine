//! Path: native/nif/src/xr_bridge.rs
//! Summary: XR 入力イベントの Elixir 送信
//!
//! desktop_input_openxr が生成した XrInputEvent を Elixir のメッセージ形式に
//! エンコードして GameEvents に送信する。

#[cfg(feature = "xr")]
use desktop_input_openxr::{ControllerButton, Hand, XrInputEvent};
use rustler::env::OwnedEnv;
use rustler::{Encoder, LocalPid};
use std::panic::AssertUnwindSafe;
use std::thread;

#[cfg(feature = "xr")]
fn encode_and_send(pid: LocalPid, event: XrInputEvent) {
    let mut env = OwnedEnv::new();
    let _ = env.send_and_clear(&pid, |env| match &event {
        XrInputEvent::HeadPose {
            position,
            orientation,
            timestamp_us,
        } => {
            let data = (
                crate::head_pose(),
                (
                    (position[0] as f64, position[1] as f64, position[2] as f64),
                    (
                        orientation[0] as f64,
                        orientation[1] as f64,
                        orientation[2] as f64,
                        orientation[3] as f64,
                    ),
                    *timestamp_us as i64,
                ),
            );
            data.encode(env)
        }
        XrInputEvent::ControllerPose {
            hand,
            position,
            orientation,
            timestamp_us,
        } => {
            let hand_atom = match hand {
                Hand::Left => crate::left(),
                Hand::Right => crate::right(),
            };
            let data = (
                crate::controller_pose(),
                (
                    hand_atom,
                    (position[0] as f64, position[1] as f64, position[2] as f64),
                    (
                        orientation[0] as f64,
                        orientation[1] as f64,
                        orientation[2] as f64,
                        orientation[3] as f64,
                    ),
                    *timestamp_us as i64,
                ),
            );
            data.encode(env)
        }
        XrInputEvent::ControllerButton {
            hand,
            button,
            pressed,
        } => {
            let hand_atom = match hand {
                Hand::Left => crate::left(),
                Hand::Right => crate::right(),
            };
            let button_atom = match button {
                ControllerButton::Trigger => crate::trigger(),
                ControllerButton::Grip => crate::grip(),
                ControllerButton::Thumbstick => crate::thumbstick(),
                ControllerButton::A => crate::a(),
                ControllerButton::B => crate::b(),
                ControllerButton::X => crate::x(),
                ControllerButton::Y => crate::y(),
                ControllerButton::Menu => crate::menu(),
                ControllerButton::System => crate::system(),
            };
            let data = (
                crate::controller_button(),
                (hand_atom, button_atom, *pressed),
            );
            data.encode(env)
        }
        XrInputEvent::TrackerPose {
            tracker_id,
            position,
            orientation,
            velocity,
            timestamp_us,
        } => {
            let velocity_term = velocity.map(|v| (v[0] as f64, v[1] as f64, v[2] as f64));
            let data = (
                crate::tracker_pose(),
                (
                    *tracker_id as i64,
                    (position[0] as f64, position[1] as f64, position[2] as f64),
                    (
                        orientation[0] as f64,
                        orientation[1] as f64,
                        orientation[2] as f64,
                        orientation[3] as f64,
                    ),
                    velocity_term,
                    *timestamp_us as i64,
                ),
            );
            data.encode(env)
        }
    });
}

/// XR 入力スレッドを起動する。
/// input_openxr::run_xr_input_loop を別スレッドで実行し、
/// イベントを Elixir に送信する。
#[cfg(feature = "xr")]
pub fn run_xr_input_thread(pid: LocalPid) {
    thread::spawn(move || {
        if let Err(e) = std::panic::catch_unwind(AssertUnwindSafe(|| {
            input_openxr::run_xr_input_loop(|event| encode_and_send(pid, event));
        })) {
            log::error!("XR input thread panicked: {:?}", e);
        }
    });
}
