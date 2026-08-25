//! OpenXR ヘッドレス入力ループ（feature = "openxr"）
//!
//! `XR_MND_headless` で描画なしセッションを作り、head / controller pose と
//! simple_controller のボタン状態を `XrInputEvent` として通知する。

use std::time::Duration;

use openxr as xr;

use crate::{ControllerButton, Hand, XrInputEvent};

const VIEW_TYPE: xr::ViewConfigurationType = xr::ViewConfigurationType::PRIMARY_STEREO;

pub(crate) fn run_openxr_loop<F>(on_event: &mut F) -> Result<(), String>
where
    F: FnMut(XrInputEvent),
{
    let entry = unsafe { xr::Entry::load() }.map_err(|e| format!("OpenXR loader: {e}"))?;

    let available = entry
        .enumerate_extensions()
        .map_err(|e| format!("enumerate_extensions: {e}"))?;
    if !available.mnd_headless {
        return Err("XR_MND_headless is not supported by the active OpenXR runtime".to_string());
    }

    let mut enabled = xr::ExtensionSet::default();
    enabled.mnd_headless = true;

    let instance = entry
        .create_instance(
            &xr::ApplicationInfo {
                application_name: "Fable XR Input",
                application_version: 1,
                engine_name: "Fable",
                engine_version: 1,
                api_version: xr::Version::new(1, 0, 0),
            },
            &enabled,
            &[],
        )
        .map_err(|e| format!("create_instance: {e}"))?;

    let props = instance
        .properties()
        .map_err(|e| format!("instance.properties: {e}"))?;
    log::info!(
        "OpenXR runtime: {} {}",
        props.runtime_name,
        props.runtime_version
    );

    let system = instance
        .system(xr::FormFactor::HEAD_MOUNTED_DISPLAY)
        .map_err(|e| format!("system(HMD): {e}"))?;

    let blend_mode = instance
        .enumerate_environment_blend_modes(system, VIEW_TYPE)
        .map_err(|e| format!("enumerate_environment_blend_modes: {e}"))?
        .into_iter()
        .next()
        .ok_or_else(|| "no environment blend modes".to_string())?;

    // Headless session has no graphics binding; create_session is unsafe in the openxr API.
    let (session, mut frame_wait, mut frame_stream) = unsafe {
        instance.create_session::<xr::Headless>(system, &xr::headless::SessionCreateInfo {})
    }
    .map_err(|e| format!("create_session(headless): {e}"))?;

    let action_set = instance
        .create_action_set("fable_input", "Fable XR input", 0)
        .map_err(|e| format!("create_action_set: {e}"))?;

    let left_pose = action_set
        .create_action::<xr::Posef>("left_hand", "Left Hand Pose", &[])
        .map_err(|e| format!("left_pose: {e}"))?;
    let right_pose = action_set
        .create_action::<xr::Posef>("right_hand", "Right Hand Pose", &[])
        .map_err(|e| format!("right_pose: {e}"))?;
    let left_select = action_set
        .create_action::<bool>("left_select", "Left Select", &[])
        .map_err(|e| format!("left_select: {e}"))?;
    let right_select = action_set
        .create_action::<bool>("right_select", "Right Select", &[])
        .map_err(|e| format!("right_select: {e}"))?;
    let left_menu = action_set
        .create_action::<bool>("left_menu", "Left Menu", &[])
        .map_err(|e| format!("left_menu: {e}"))?;
    let right_menu = action_set
        .create_action::<bool>("right_menu", "Right Menu", &[])
        .map_err(|e| format!("right_menu: {e}"))?;

    let path = |s: &str| {
        instance
            .string_to_path(s)
            .map_err(|e| format!("path {s}: {e}"))
    };
    instance
        .suggest_interaction_profile_bindings(
            path("/interaction_profiles/khr/simple_controller")?,
            &[
                xr::Binding::new(&left_pose, path("/user/hand/left/input/grip/pose")?),
                xr::Binding::new(&right_pose, path("/user/hand/right/input/grip/pose")?),
                xr::Binding::new(&left_select, path("/user/hand/left/input/select/click")?),
                xr::Binding::new(&right_select, path("/user/hand/right/input/select/click")?),
                xr::Binding::new(&left_menu, path("/user/hand/left/input/menu/click")?),
                xr::Binding::new(&right_menu, path("/user/hand/right/input/menu/click")?),
            ],
        )
        .map_err(|e| format!("suggest_interaction_profile_bindings: {e}"))?;

    session
        .attach_action_sets(&[&action_set])
        .map_err(|e| format!("attach_action_sets: {e}"))?;

    let left_space = left_pose
        .create_space(&session, xr::Path::NULL, xr::Posef::IDENTITY)
        .map_err(|e| format!("left_space: {e}"))?;
    let right_space = right_pose
        .create_space(&session, xr::Path::NULL, xr::Posef::IDENTITY)
        .map_err(|e| format!("right_space: {e}"))?;

    let local = session
        .create_reference_space(xr::ReferenceSpaceType::LOCAL, xr::Posef::IDENTITY)
        .map_err(|e| format!("LOCAL space: {e}"))?;
    let view = session
        .create_reference_space(xr::ReferenceSpaceType::VIEW, xr::Posef::IDENTITY)
        .map_err(|e| format!("VIEW space: {e}"))?;

    let mut event_storage = xr::EventDataBuffer::new();
    let mut session_running = false;
    let mut left_select_prev = false;
    let mut right_select_prev = false;
    let mut left_menu_prev = false;
    let mut right_menu_prev = false;

    log::info!("OpenXR headless input loop started");

    'main: loop {
        while let Some(event) = instance
            .poll_event(&mut event_storage)
            .map_err(|e| format!("poll_event: {e}"))?
        {
            use xr::Event::*;
            match event {
                SessionStateChanged(e) => match e.state() {
                    xr::SessionState::READY => {
                        session
                            .begin(VIEW_TYPE)
                            .map_err(|e| format!("session.begin: {e}"))?;
                        session_running = true;
                        log::info!("OpenXR session READY → begun");
                    }
                    xr::SessionState::STOPPING => {
                        session.end().map_err(|e| format!("session.end: {e}"))?;
                        session_running = false;
                        log::info!("OpenXR session STOPPING → ended");
                    }
                    xr::SessionState::EXITING | xr::SessionState::LOSS_PENDING => {
                        break 'main;
                    }
                    _ => {}
                },
                InstanceLossPending(_) => break 'main,
                EventsLost(e) => {
                    log::warn!("OpenXR lost {} events", e.lost_event_count());
                }
                _ => {}
            }
        }

        if !session_running {
            std::thread::sleep(Duration::from_millis(50));
            continue;
        }

        let frame_state = frame_wait.wait().map_err(|e| format!("frame_wait: {e}"))?;
        frame_stream
            .begin()
            .map_err(|e| format!("frame_stream.begin: {e}"))?;

        let display_time = frame_state.predicted_display_time;
        let timestamp_us = time_to_us(display_time);

        session
            .sync_actions(&[(&action_set).into()])
            .map_err(|e| format!("sync_actions: {e}"))?;

        if let Ok(loc) = view.locate(&local, display_time) {
            if pose_valid(loc.location_flags) {
                on_event(XrInputEvent::HeadPose {
                    position: vec3(loc.pose.position),
                    orientation: quat(loc.pose.orientation),
                    timestamp_us,
                });
            }
        }

        emit_controller_pose(
            on_event,
            &session,
            Hand::Left,
            &left_pose,
            &left_space,
            &local,
            display_time,
        );
        emit_controller_pose(
            on_event,
            &session,
            Hand::Right,
            &right_pose,
            &right_space,
            &local,
            display_time,
        );

        emit_button_change(
            on_event,
            &session,
            &left_select,
            Hand::Left,
            ControllerButton::Trigger,
            &mut left_select_prev,
        );
        emit_button_change(
            on_event,
            &session,
            &right_select,
            Hand::Right,
            ControllerButton::Trigger,
            &mut right_select_prev,
        );
        emit_button_change(
            on_event,
            &session,
            &left_menu,
            Hand::Left,
            ControllerButton::Menu,
            &mut left_menu_prev,
        );
        emit_button_change(
            on_event,
            &session,
            &right_menu,
            Hand::Right,
            ControllerButton::Menu,
            &mut right_menu_prev,
        );

        frame_stream
            .end(display_time, blend_mode, &[])
            .map_err(|e| format!("frame_stream.end: {e}"))?;
    }

    log::info!("OpenXR input loop exited");
    Ok(())
}

fn emit_controller_pose<F, G>(
    on_event: &mut F,
    session: &xr::Session<G>,
    hand: Hand,
    action: &xr::Action<xr::Posef>,
    space: &xr::Space,
    base: &xr::Space,
    display_time: xr::Time,
) where
    F: FnMut(XrInputEvent),
    G: xr::Graphics,
{
    let active = action.is_active(session, xr::Path::NULL).unwrap_or(false);
    if !active {
        return;
    }
    let Ok(loc) = space.locate(base, display_time) else {
        return;
    };
    if !pose_valid(loc.location_flags) {
        return;
    }
    on_event(XrInputEvent::ControllerPose {
        hand,
        position: vec3(loc.pose.position),
        orientation: quat(loc.pose.orientation),
        timestamp_us: time_to_us(display_time),
    });
}

fn emit_button_change<F, G>(
    on_event: &mut F,
    session: &xr::Session<G>,
    action: &xr::Action<bool>,
    hand: Hand,
    button: ControllerButton,
    prev: &mut bool,
) where
    F: FnMut(XrInputEvent),
    G: xr::Graphics,
{
    let Ok(state) = action.state(session, xr::Path::NULL) else {
        return;
    };
    if !state.is_active {
        return;
    }
    let pressed = state.current_state;
    if pressed != *prev {
        *prev = pressed;
        on_event(XrInputEvent::ControllerButton {
            hand,
            button,
            pressed,
        });
    }
}

fn pose_valid(flags: xr::SpaceLocationFlags) -> bool {
    flags.contains(xr::SpaceLocationFlags::POSITION_VALID)
        && flags.contains(xr::SpaceLocationFlags::ORIENTATION_VALID)
}

fn vec3(v: xr::Vector3f) -> [f32; 3] {
    [v.x, v.y, v.z]
}

fn quat(q: xr::Quaternionf) -> [f32; 4] {
    [q.x, q.y, q.z, q.w]
}

fn time_to_us(t: xr::Time) -> u64 {
    (t.as_nanos().max(0) as u64) / 1_000
}
