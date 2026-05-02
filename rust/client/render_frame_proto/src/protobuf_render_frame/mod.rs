//! `proto/render_frame.proto` 由来のバイト列を `RenderFrame` にデコードする（Elixir / Zenoh / NIF 共通）。
//!
//! # デコード方針（緩いデコード）
//!
//! - `repeated float` や可変長フィールドが **短い・欠損**している場合、`f2` / `f4` / `f3` は **0 を埋める**（`f4` の alpha は 1.0）。
//! - エンコーダバグの検知を遅らせうるため、厳密な検証が必要なら **契約テスト**（`tests/decode_contract.rs` 等）で担保する。
//! - `uint32` → `u8` は飽和し、超過時は [`log::warn!`] する。

mod draw_command;
mod float_helpers;
mod mesh_helpers;

use crate::pb;
use prost::Message;
use shared::render_frame::{
    CameraParams, MeshDef, RenderFrame, UiAnchor, UiCanvas, UiComponent, UiNode, UiRect, UiSize,
};

use draw_command::draw_cmd_pb;
use float_helpers::{f2, f3, f4, pad4};
use mesh_helpers::mesh_def_pb;

pub(super) fn u32_to_u8_clamped(field: &'static str, v: u32) -> u8 {
    if v > u8::MAX as u32 {
        log::warn!(
            "protobuf_render_frame: {} value {} exceeds u8::MAX, clamping",
            field,
            v
        );
        u8::MAX
    } else {
        v as u8
    }
}

/// 空の `bytes` は protobuf 上「空の `RenderFrame`」として **成功**しうる。
/// 境界では空拒否など呼び出し側のポリシーで補う（本クレート先頭の「空ペイロード」節を参照）。
pub fn decode_pb_render_frame(bytes: &[u8]) -> Result<RenderFrame, prost::DecodeError> {
    let pb = pb::RenderFrame::decode(bytes)?;
    Ok(pb_into_render_frame(pb))
}

fn pb_into_render_frame(pb: pb::RenderFrame) -> RenderFrame {
    let mut commands = Vec::with_capacity(pb.commands.len());
    for cmd in pb.commands {
        if let Some(c) = draw_cmd_pb(cmd) {
            commands.push(c);
        }
    }
    let camera = pb
        .camera
        .map(camera_pb)
        .unwrap_or_else(|| CameraParams::Camera2D {
            offset_x: 0.0,
            offset_y: 0.0,
        });
    let ui = pb.ui.map(ui_canvas_pb).unwrap_or_default();
    let mesh_definitions: Vec<MeshDef> = pb.mesh_definitions.into_iter().map(mesh_def_pb).collect();
    let cursor_grab = pb.cursor_grab.and_then(|v| match v {
        x if x == pb::CursorGrabKind::CursorGrabGrab as i32 => Some(true),
        x if x == pb::CursorGrabKind::CursorGrabRelease as i32 => Some(false),
        _ => None,
    });

    let audio_cues = pb.audio_cues;

    RenderFrame {
        commands,
        camera,
        ui,
        cursor_grab,
        mesh_definitions,
        audio_cues,
    }
}

fn camera_pb(c: pb::CameraParams) -> CameraParams {
    use pb::camera_params::Kind::*;
    match c.kind {
        Some(Camera2d(c2)) => CameraParams::Camera2D {
            offset_x: c2.offset_x,
            offset_y: c2.offset_y,
        },
        Some(Camera3d(c3)) => CameraParams::Camera3D {
            eye: f3(&c3.eye),
            target: f3(&c3.target),
            up: f3(&c3.up),
            fov_deg: c3.fov_deg,
            near: c3.near,
            far: c3.far,
        },
        None => CameraParams::default(),
    }
}

fn ui_canvas_pb(c: pb::UiCanvas) -> UiCanvas {
    UiCanvas {
        nodes: c.nodes.into_iter().map(ui_node_pb).collect(),
    }
}

fn ui_node_pb(n: pb::UiNode) -> UiNode {
    UiNode {
        rect: n.rect.map(ui_rect_pb).unwrap_or_default(),
        component: n
            .component
            .map(ui_component_pb)
            .unwrap_or(UiComponent::Separator),
        children: n.children.into_iter().map(ui_node_pb).collect(),
    }
}

fn ui_anchor_from_str(s: &str) -> UiAnchor {
    match s {
        "top_left" => UiAnchor::TopLeft,
        "top_center" => UiAnchor::TopCenter,
        "top_right" => UiAnchor::TopRight,
        "middle_left" => UiAnchor::MiddleLeft,
        "center" => UiAnchor::Center,
        "middle_right" => UiAnchor::MiddleRight,
        "bottom_left" => UiAnchor::BottomLeft,
        "bottom_center" => UiAnchor::BottomCenter,
        "bottom_right" => UiAnchor::BottomRight,
        "" => UiAnchor::TopLeft,
        other => {
            log::warn!(
                "protobuf_render_frame: unknown UiRect.anchor {:?}, using TopLeft",
                other
            );
            UiAnchor::TopLeft
        }
    }
}

fn ui_rect_pb(r: pb::UiRect) -> UiRect {
    let size = match r.size {
        Some(pb::ui_rect::Size::Wrap(_)) | None => UiSize::WrapContent,
        Some(pb::ui_rect::Size::Fixed(f)) => UiSize::Fixed(f.w, f.h),
    };
    UiRect {
        anchor: ui_anchor_from_str(&r.anchor),
        offset: f2(&r.offset),
        size,
    }
}

fn ui_component_pb(c: pb::UiComponent) -> UiComponent {
    use pb::ui_component::Kind::*;
    match c.kind {
        None => {
            log::warn!("protobuf_render_frame: UiComponent missing kind, using Separator");
            UiComponent::Separator
        }
        Some(Separator(_)) => UiComponent::Separator,
        Some(VerticalLayout(v)) => UiComponent::VerticalLayout {
            spacing: v.spacing,
            padding: pad4(&v.padding),
        },
        Some(HorizontalLayout(v)) => UiComponent::HorizontalLayout {
            spacing: v.spacing,
            padding: pad4(&v.padding),
        },
        Some(Rect(st)) => {
            let border = st.border.map(|b| (f4(&b.color), b.width));
            UiComponent::Rect {
                color: f4(&st.color),
                corner_radius: st.corner_radius,
                border,
            }
        }
        Some(Text(t)) => UiComponent::Text {
            text: t.text,
            color: f4(&t.color),
            size: t.size,
            bold: t.bold,
        },
        Some(Button(b)) => UiComponent::Button {
            label: b.label,
            action: b.action,
            color: f4(&b.color),
            min_width: b.min_width,
            min_height: b.min_height,
        },
        Some(ProgressBar(p)) => UiComponent::ProgressBar {
            value: p.value,
            max: p.max,
            width: p.width,
            height: p.height,
            fg_color_high: f4(&p.fg_color_high),
            fg_color_mid: f4(&p.fg_color_mid),
            fg_color_low: f4(&p.fg_color_low),
            bg_color: f4(&p.bg_color),
            corner_radius: p.corner_radius,
        },
        Some(Spacing(s)) => UiComponent::Spacing { amount: s.amount },
        Some(WorldText(w)) => UiComponent::WorldText {
            world_x: w.world_x,
            world_y: w.world_y,
            world_z: w.world_z,
            text: w.text,
            color: f4(&w.color),
            lifetime: w.lifetime,
            max_lifetime: w.max_lifetime,
        },
        Some(ScreenFlash(s)) => UiComponent::ScreenFlash {
            color: f4(&s.color),
        },
    }
}
