//! Zenoh 用 RenderFrame の protobuf（ネイティブ）デコード。
//! `proto/render_frame.proto` とフィールド番号を一致させる。

use prost::Message;
use render::{
    CameraParams, DrawCommand, MeshDef, MeshVertex, RenderFrame, UiAnchor, UiCanvas, UiComponent,
    UiNode, UiRect, UiSize,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, prost::Enumeration)]
#[repr(i32)]
pub enum CursorGrabKind {
    Unspecified = 0,
    Grab = 1,
    Release = 2,
}

#[derive(Clone, PartialEq, Message)]
pub struct PbRenderFrame {
    #[prost(message, repeated, tag = "1")]
    pub commands: Vec<DrawCommandPb>,
    #[prost(message, optional, tag = "2")]
    pub camera: Option<CameraParamsPb>,
    #[prost(message, optional, tag = "3")]
    pub ui: Option<UiCanvasPb>,
    #[prost(message, repeated, tag = "4")]
    pub mesh_definitions: Vec<MeshDefPb>,
    #[prost(optional, enumeration = "CursorGrabKind", tag = "5")]
    pub cursor_grab: Option<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct DrawCommandPb {
    #[prost(oneof = "draw_command_pb::Kind", tags = "1,2,3,4,5,6,7,8,9")]
    pub kind: Option<draw_command_pb::Kind>,
}

pub mod draw_command_pb {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Kind {
        #[prost(message, tag = "1")]
        PlayerSprite(super::PlayerSpritePb),
        #[prost(message, tag = "2")]
        SpriteRaw(super::SpriteRawPb),
        #[prost(message, tag = "3")]
        Particle(super::ParticleCmdPb),
        #[prost(message, tag = "4")]
        Item(super::ItemCmdPb),
        #[prost(message, tag = "5")]
        Obstacle(super::ObstacleCmdPb),
        #[prost(message, tag = "6")]
        Box3d(super::Box3dCmdPb),
        #[prost(message, tag = "7")]
        GridPlane(super::GridPlaneCmdPb),
        #[prost(message, tag = "8")]
        GridPlaneVerts(super::GridPlaneVertsCmdPb),
        #[prost(message, tag = "9")]
        Skybox(super::SkyboxCmdPb),
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct PlayerSpritePb {
    #[prost(float, tag = "1")]
    pub x: f32,
    #[prost(float, tag = "2")]
    pub y: f32,
    #[prost(uint32, tag = "3")]
    pub frame: u32,
}

#[derive(Clone, PartialEq, Message)]
pub struct SpriteRawPb {
    #[prost(float, tag = "1")]
    pub x: f32,
    #[prost(float, tag = "2")]
    pub y: f32,
    #[prost(float, tag = "3")]
    pub width: f32,
    #[prost(float, tag = "4")]
    pub height: f32,
    #[prost(float, repeated, tag = "5")]
    pub uv_offset: Vec<f32>,
    #[prost(float, repeated, tag = "6")]
    pub uv_size: Vec<f32>,
    #[prost(float, repeated, tag = "7")]
    pub color_tint: Vec<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct ParticleCmdPb {
    #[prost(float, tag = "1")]
    pub x: f32,
    #[prost(float, tag = "2")]
    pub y: f32,
    #[prost(float, tag = "3")]
    pub r: f32,
    #[prost(float, tag = "4")]
    pub g: f32,
    #[prost(float, tag = "5")]
    pub b: f32,
    #[prost(float, tag = "6")]
    pub alpha: f32,
    #[prost(float, tag = "7")]
    pub size: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct ItemCmdPb {
    #[prost(float, tag = "1")]
    pub x: f32,
    #[prost(float, tag = "2")]
    pub y: f32,
    #[prost(uint32, tag = "3")]
    pub kind: u32,
}

#[derive(Clone, PartialEq, Message)]
pub struct ObstacleCmdPb {
    #[prost(float, tag = "1")]
    pub x: f32,
    #[prost(float, tag = "2")]
    pub y: f32,
    #[prost(float, tag = "3")]
    pub radius: f32,
    #[prost(uint32, tag = "4")]
    pub kind: u32,
}

#[derive(Clone, PartialEq, Message)]
pub struct Box3dCmdPb {
    #[prost(float, tag = "1")]
    pub x: f32,
    #[prost(float, tag = "2")]
    pub y: f32,
    #[prost(float, tag = "3")]
    pub z: f32,
    #[prost(float, tag = "4")]
    pub half_w: f32,
    #[prost(float, tag = "5")]
    pub half_h: f32,
    #[prost(float, tag = "6")]
    pub half_d: f32,
    #[prost(float, repeated, tag = "7")]
    pub color: Vec<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct GridPlaneCmdPb {
    #[prost(float, tag = "1")]
    pub size: f32,
    #[prost(uint32, tag = "2")]
    pub divisions: u32,
    #[prost(float, repeated, tag = "3")]
    pub color: Vec<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct GridPlaneVertsCmdPb {
    #[prost(message, repeated, tag = "1")]
    pub vertices: Vec<MeshVertexPb>,
}

#[derive(Clone, PartialEq, Message)]
pub struct SkyboxCmdPb {
    #[prost(float, repeated, tag = "1")]
    pub top_color: Vec<f32>,
    #[prost(float, repeated, tag = "2")]
    pub bottom_color: Vec<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct MeshVertexPb {
    #[prost(float, repeated, tag = "1")]
    pub position: Vec<f32>,
    #[prost(float, repeated, tag = "2")]
    pub color: Vec<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct MeshDefPb {
    #[prost(string, tag = "1")]
    pub name: String,
    #[prost(message, repeated, tag = "2")]
    pub vertices: Vec<MeshVertexPb>,
    #[prost(uint32, repeated, tag = "3")]
    pub indices: Vec<u32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct CameraParamsPb {
    #[prost(oneof = "camera_params_pb::Kind", tags = "1,2")]
    pub kind: Option<camera_params_pb::Kind>,
}

pub mod camera_params_pb {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Kind {
        #[prost(message, tag = "1")]
        Camera2d(super::Camera2dPb),
        #[prost(message, tag = "2")]
        Camera3d(super::Camera3dPb),
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct Camera2dPb {
    #[prost(float, tag = "1")]
    pub offset_x: f32,
    #[prost(float, tag = "2")]
    pub offset_y: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct Camera3dPb {
    #[prost(float, repeated, tag = "1")]
    pub eye: Vec<f32>,
    #[prost(float, repeated, tag = "2")]
    pub target: Vec<f32>,
    #[prost(float, repeated, tag = "3")]
    pub up: Vec<f32>,
    #[prost(float, tag = "4")]
    pub fov_deg: f32,
    #[prost(float, tag = "5")]
    pub near: f32,
    #[prost(float, tag = "6")]
    pub far: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiCanvasPb {
    #[prost(message, repeated, tag = "1")]
    pub nodes: Vec<UiNodePb>,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiNodePb {
    #[prost(message, optional, tag = "1")]
    pub rect: Option<UiRectPb>,
    #[prost(message, optional, tag = "2")]
    pub component: Option<UiComponentPb>,
    #[prost(message, repeated, tag = "3")]
    pub children: Vec<UiNodePb>,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiRectPb {
    #[prost(string, tag = "1")]
    pub anchor: String,
    #[prost(float, repeated, tag = "2")]
    pub offset: Vec<f32>,
    #[prost(oneof = "ui_rect_pb::Size", tags = "3,4")]
    pub size: Option<ui_rect_pb::Size>,
}

pub mod ui_rect_pb {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Size {
        #[prost(message, tag = "3")]
        Wrap(super::UiSizeWrapPb),
        #[prost(message, tag = "4")]
        Fixed(super::UiSizeFixedPb),
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct UiSizeWrapPb {}

#[derive(Clone, PartialEq, Message)]
pub struct UiSizeFixedPb {
    #[prost(float, tag = "1")]
    pub w: f32,
    #[prost(float, tag = "2")]
    pub h: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiComponentPb {
    #[prost(oneof = "ui_component_pb::Kind", tags = "1,2,3,4,5,6,7,8,9,10")]
    pub kind: Option<ui_component_pb::Kind>,
}

pub mod ui_component_pb {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Kind {
        #[prost(message, tag = "1")]
        Separator(super::UiSeparatorPb),
        #[prost(message, tag = "2")]
        VerticalLayout(super::UiVerticalLayoutPb),
        #[prost(message, tag = "3")]
        HorizontalLayout(super::UiHorizontalLayoutPb),
        #[prost(message, tag = "4")]
        Rect(super::UiRectStylePb),
        #[prost(message, tag = "5")]
        Text(super::UiTextPb),
        #[prost(message, tag = "6")]
        Button(super::UiButtonPb),
        #[prost(message, tag = "7")]
        ProgressBar(super::UiProgressBarPb),
        #[prost(message, tag = "8")]
        Spacing(super::UiSpacingPb),
        #[prost(message, tag = "9")]
        WorldText(super::UiWorldTextPb),
        #[prost(message, tag = "10")]
        ScreenFlash(super::UiScreenFlashPb),
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct UiSeparatorPb {}

#[derive(Clone, PartialEq, Message)]
pub struct UiVerticalLayoutPb {
    #[prost(float, tag = "1")]
    pub spacing: f32,
    #[prost(float, repeated, tag = "2")]
    pub padding: Vec<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiHorizontalLayoutPb {
    #[prost(float, tag = "1")]
    pub spacing: f32,
    #[prost(float, repeated, tag = "2")]
    pub padding: Vec<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiRectStylePb {
    #[prost(float, repeated, tag = "1")]
    pub color: Vec<f32>,
    #[prost(float, tag = "2")]
    pub corner_radius: f32,
    #[prost(message, optional, tag = "3")]
    pub border: Option<UiBorderPb>,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiBorderPb {
    #[prost(float, repeated, tag = "1")]
    pub color: Vec<f32>,
    #[prost(float, tag = "2")]
    pub width: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiTextPb {
    #[prost(string, tag = "1")]
    pub text: String,
    #[prost(float, repeated, tag = "2")]
    pub color: Vec<f32>,
    #[prost(float, tag = "3")]
    pub size: f32,
    #[prost(bool, tag = "4")]
    pub bold: bool,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiButtonPb {
    #[prost(string, tag = "1")]
    pub label: String,
    #[prost(string, tag = "2")]
    pub action: String,
    #[prost(float, repeated, tag = "3")]
    pub color: Vec<f32>,
    #[prost(float, tag = "4")]
    pub min_width: f32,
    #[prost(float, tag = "5")]
    pub min_height: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiProgressBarPb {
    #[prost(float, tag = "1")]
    pub value: f32,
    #[prost(float, tag = "2")]
    pub max: f32,
    #[prost(float, tag = "3")]
    pub width: f32,
    #[prost(float, tag = "4")]
    pub height: f32,
    #[prost(float, repeated, tag = "5")]
    pub fg_color_high: Vec<f32>,
    #[prost(float, repeated, tag = "6")]
    pub fg_color_mid: Vec<f32>,
    #[prost(float, repeated, tag = "7")]
    pub fg_color_low: Vec<f32>,
    #[prost(float, repeated, tag = "8")]
    pub bg_color: Vec<f32>,
    #[prost(float, tag = "9")]
    pub corner_radius: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiSpacingPb {
    #[prost(float, tag = "1")]
    pub amount: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiWorldTextPb {
    #[prost(float, tag = "1")]
    pub world_x: f32,
    #[prost(float, tag = "2")]
    pub world_y: f32,
    #[prost(float, tag = "3")]
    pub world_z: f32,
    #[prost(string, tag = "4")]
    pub text: String,
    #[prost(float, repeated, tag = "5")]
    pub color: Vec<f32>,
    #[prost(float, tag = "6")]
    pub lifetime: f32,
    #[prost(float, tag = "7")]
    pub max_lifetime: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct UiScreenFlashPb {
    #[prost(float, repeated, tag = "1")]
    pub color: Vec<f32>,
}

pub fn decode_pb_render_frame(bytes: &[u8]) -> Result<RenderFrame, prost::DecodeError> {
    let pb = PbRenderFrame::decode(bytes)?;
    Ok(pb_into_render_frame(pb))
}

fn pb_into_render_frame(pb: PbRenderFrame) -> RenderFrame {
    let commands: Vec<DrawCommand> = pb.commands.into_iter().filter_map(draw_cmd_pb).collect();
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
        x if x == CursorGrabKind::Grab as i32 => Some(true),
        x if x == CursorGrabKind::Release as i32 => Some(false),
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

fn draw_cmd_pb(cmd: DrawCommandPb) -> Option<DrawCommand> {
    use draw_command_pb::Kind::*;
    let k = cmd.kind?;
    Some(match k {
        PlayerSprite(p) => DrawCommand::PlayerSprite {
            x: p.x,
            y: p.y,
            frame: p.frame as u8,
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
            kind: i.kind as u8,
        },
        Obstacle(o) => DrawCommand::Obstacle {
            x: o.x,
            y: o.y,
            radius: o.radius,
            kind: o.kind as u8,
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

fn mesh_vertex_pb(v: MeshVertexPb) -> MeshVertex {
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

fn mesh_def_pb(m: MeshDefPb) -> MeshDef {
    MeshDef {
        name: m.name,
        vertices: m.vertices.into_iter().map(mesh_vertex_pb).collect(),
        indices: m.indices,
    }
}

fn camera_pb(c: CameraParamsPb) -> CameraParams {
    use camera_params_pb::Kind::*;
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

fn ui_canvas_pb(c: UiCanvasPb) -> UiCanvas {
    UiCanvas {
        nodes: c.nodes.into_iter().map(ui_node_pb).collect(),
    }
}

fn ui_node_pb(n: UiNodePb) -> UiNode {
    UiNode {
        rect: n.rect.map(ui_rect_pb).unwrap_or_default(),
        component: n.component.map(ui_component_pb).unwrap_or(UiComponent::Separator),
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
        _ => UiAnchor::TopLeft,
    }
}

fn ui_rect_pb(r: UiRectPb) -> UiRect {
    let size = match r.size {
        Some(ui_rect_pb::Size::Wrap(_)) | None => UiSize::WrapContent,
        Some(ui_rect_pb::Size::Fixed(f)) => UiSize::Fixed(f.w, f.h),
    };
    UiRect {
        anchor: ui_anchor_from_str(&r.anchor),
        offset: f2(&r.offset),
        size,
    }
}

fn ui_component_pb(c: UiComponentPb) -> UiComponent {
    use ui_component_pb::Kind::*;
    match c.kind {
        Some(Separator(_)) | None => UiComponent::Separator,
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
