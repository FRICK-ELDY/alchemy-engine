//! `proto/render_frame.proto` 由来のバイト列を `RenderFrame` にデコードする（Elixir / Zenoh / NIF 共通）。
//!
//! # デコード方針（緩いデコード）
//!
//! - `repeated float` や可変長フィールドが **短い・欠損**している場合、`f2` / `f4` / `f3` は **0 を埋める**（`f4` の alpha は 1.0）。
//! - エンコーダバグの検知を遅らせうるため、厳密な検証が必要なら **契約テスト**（`tests/decode_contract.rs` 等）で担保する。
//! - `uint32` → `u8` は飽和し、超過時は [`log::warn!`] する。

use crate::pb;
use prost::Message;
use shared::render_frame::{
    CameraParams, DrawCommand, MeshDef, MeshVertex, RenderFrame, UiAnchor, UiCanvas, UiComponent,
    UiNode, UiRect, UiSize,
};

fn u32_to_u8_clamped(field: &'static str, v: u32) -> u8 {
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

    RenderFrame {
        commands,
        camera,
        ui,
        cursor_grab,
        mesh_definitions,
    }
}

fn draw_cmd_pb(cmd: pb::DrawCommand) -> Option<DrawCommand> {
    use pb::draw_command::Kind::*;
    let k = match cmd.kind {
        Some(k) => k,
        None => {
            log::warn!("protobuf_render_frame: DrawCommand skipped (missing kind)");
            return None;
        }
    };
    Some(match k {
        PlayerSprite(p) => DrawCommand::PlayerSprite {
            x: p.x,
            y: p.y,
            frame: u32_to_u8_clamped("player_sprite.frame", p.frame),
        },
        SpriteRaw(s) => DrawCommand::SpriteRaw {
            x: s.x,
            y: s.y,
            width: s.width,
            height: s.height,
            uv_offset: f2(&s.uv_offset),
            uv_size: f2(&s.uv_size),
            color_tint: f4(&s.color_tint),
        },
        Particle(p) => DrawCommand::Particle {
            x: p.x,
            y: p.y,
            r: p.r,
            g: p.g,
            b: p.b,
            alpha: p.alpha,
            size: p.size,
        },
        Item(i) => DrawCommand::Item {
            x: i.x,
            y: i.y,
            kind: u32_to_u8_clamped("item.kind", i.kind),
        },
        Obstacle(o) => DrawCommand::Obstacle {
            x: o.x,
            y: o.y,
            radius: o.radius,
            kind: u32_to_u8_clamped("obstacle.kind", o.kind),
        },
        Box3d(b) => DrawCommand::Box3D {
            x: b.x,
            y: b.y,
            z: b.z,
            half_w: b.half_w,
            half_h: b.half_h,
            half_d: b.half_d,
            color: f4(&b.color),
        },
        GridPlane(g) => DrawCommand::GridPlane {
            size: g.size,
            divisions: g.divisions,
            color: f4(&g.color),
        },
        GridPlaneVerts(g) => DrawCommand::GridPlaneVerts {
            vertices: g.vertices.into_iter().map(mesh_vertex_pb).collect(),
        },
        Skybox(s) => DrawCommand::Skybox {
            top_color: f4(&s.top_color),
            bottom_color: f4(&s.bottom_color),
        },
    })
}

fn f2(v: &[f32]) -> [f32; 2] {
    [
        v.first().copied().unwrap_or(0.0),
        v.get(1).copied().unwrap_or(0.0),
    ]
}

fn f4(v: &[f32]) -> [f32; 4] {
    [
        v.first().copied().unwrap_or(0.0),
        v.get(1).copied().unwrap_or(0.0),
        v.get(2).copied().unwrap_or(0.0),
        v.get(3).copied().unwrap_or(1.0),
    ]
}

fn mesh_vertex_pb(v: pb::MeshVertex) -> MeshVertex {
    let p = &v.position;
    let c = &v.color;
    MeshVertex {
        position: [
            p.first().copied().unwrap_or(0.0),
            p.get(1).copied().unwrap_or(0.0),
            p.get(2).copied().unwrap_or(0.0),
        ],
        color: f4(c),
    }
}

fn mesh_def_pb(m: pb::MeshDef) -> MeshDef {
    MeshDef {
        name: m.name,
        vertices: m.vertices.into_iter().map(mesh_vertex_pb).collect(),
        indices: m.indices,
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

fn f3(v: &[f32]) -> [f32; 3] {
    [
        v.first().copied().unwrap_or(0.0),
        v.get(1).copied().unwrap_or(0.0),
        v.get(2).copied().unwrap_or(0.0),
    ]
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

fn pad4(v: &[f32]) -> [f32; 4] {
    [
        v.first().copied().unwrap_or(0.0),
        v.get(1).copied().unwrap_or(0.0),
        v.get(2).copied().unwrap_or(0.0),
        v.get(3).copied().unwrap_or(0.0),
    ]
}
