//! Path: native/nif/src/nif/decode/msgpack.rs
//! Summary: P5-2 MessagePack バイナリ → RenderFrame 変換
//!
//! Elixir の msgpax で pack されたバイナリを rmp-serde でデコードし、
//! desktop_render::RenderFrame に変換する。スキーマ: docs/architecture/messagepack-schema.md

use desktop_render::{
    CameraParams, DrawCommand, MeshDef, MeshVertex, RenderFrame, UiAnchor, UiCanvas, UiComponent,
    UiNode, UiRect, UiSize,
};
use rmp_serde::from_slice;
use serde::Deserialize;

/// フレーム全体の MessagePack 構造
#[derive(Deserialize)]
struct FrameMsg {
    commands: Vec<DrawCommandMsg>,
    camera: CameraMsg,
    ui: UiCanvasMsg,
    mesh_definitions: Vec<MeshDefMsg>,
}

#[derive(Deserialize)]
#[serde(tag = "t")]
enum DrawCommandMsg {
    #[serde(rename = "player_sprite")]
    PlayerSprite { x: f64, y: f64, frame: u8 },
    #[serde(rename = "sprite_raw")]
    SpriteRaw {
        x: f64,
        y: f64,
        width: f64,
        height: f64,
        uv_offset: [f64; 2],
        uv_size: [f64; 2],
        color_tint: [f64; 4],
    },
    #[serde(rename = "particle")]
    Particle {
        x: f64,
        y: f64,
        r: f64,
        g: f64,
        b: f64,
        alpha: f64,
        size: f64,
    },
    #[serde(rename = "item")]
    Item { x: f64, y: f64, kind: u8 },
    #[serde(rename = "obstacle")]
    Obstacle {
        x: f64,
        y: f64,
        radius: f64,
        kind: u8,
    },
    #[serde(rename = "box_3d")]
    Box3D {
        x: f64,
        y: f64,
        z: f64,
        half_w: f64,
        half_h: f64,
        half_d: f64,
        color: [f64; 4],
    },
    #[serde(rename = "grid_plane")]
    GridPlane {
        size: f64,
        divisions: u32,
        color: [f64; 4],
    },
    #[serde(rename = "grid_plane_verts")]
    GridPlaneVerts { vertices: Vec<VertexWire> },
    #[serde(rename = "skybox")]
    Skybox {
        top_color: [f64; 4],
        bottom_color: [f64; 4],
    },
}

/// [[x,y,z],[r,g,b,a]] 形式の頂点
#[derive(Deserialize)]
struct VertexWire(Vec<f64>, Vec<f64>);

impl VertexWire {
    fn to_mesh_vertex(&self) -> MeshVertex {
        let p = &self.0;
        let c = &self.1;
        MeshVertex {
            position: [
                p.get(0).copied().unwrap_or(0.0) as f32,
                p.get(1).copied().unwrap_or(0.0) as f32,
                p.get(2).copied().unwrap_or(0.0) as f32,
            ],
            color: [
                c.get(0).copied().unwrap_or(0.0) as f32,
                c.get(1).copied().unwrap_or(0.0) as f32,
                c.get(2).copied().unwrap_or(0.0) as f32,
                c.get(3).copied().unwrap_or(1.0) as f32,
            ],
        }
    }
}

#[derive(Deserialize)]
#[serde(tag = "t")]
enum CameraMsg {
    #[serde(rename = "camera_2d")]
    Camera2D { offset_x: f64, offset_y: f64 },
    #[serde(rename = "camera_3d")]
    Camera3D {
        eye: [f64; 3],
        target: [f64; 3],
        up: [f64; 3],
        fov_deg: f64,
        near: f64,
        far: f64,
    },
}

#[derive(Deserialize)]
struct UiCanvasMsg {
    nodes: Vec<UiNodeMsg>,
}

#[derive(Deserialize)]
struct UiNodeMsg {
    rect: UiRectMsg,
    component: UiComponentMsg,
    children: Vec<UiNodeMsg>,
}

#[derive(Deserialize)]
struct UiRectMsg {
    anchor: String,
    offset: [f64; 2],
    size: UiSizeWire,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum UiSizeWire {
    #[allow(dead_code)]
    Wrap(String),
    Fixed([f64; 2]),
}

#[derive(Deserialize)]
#[serde(tag = "t")]
enum UiComponentMsg {
    #[serde(rename = "vertical_layout")]
    VerticalLayout { spacing: f64, padding: [f64; 4] },
    #[serde(rename = "horizontal_layout")]
    HorizontalLayout { spacing: f64, padding: [f64; 4] },
    #[serde(rename = "separator")]
    Separator,
    #[serde(rename = "rect")]
    Rect {
        color: [f64; 4],
        corner_radius: f64,
        #[serde(default)]
        border: Option<(Vec<f64>, f64)>,
    },
    #[serde(rename = "text")]
    Text {
        text: String,
        color: [f64; 4],
        size: f64,
        bold: bool,
    },
    #[serde(rename = "button")]
    Button {
        label: String,
        action: String,
        color: [f64; 4],
        min_width: f64,
        min_height: f64,
    },
    #[serde(rename = "progress_bar")]
    ProgressBar {
        value: f64,
        max: f64,
        width: f64,
        height: f64,
        fg_color_high: [f64; 4],
        fg_color_mid: [f64; 4],
        fg_color_low: [f64; 4],
        bg_color: [f64; 4],
        corner_radius: f64,
    },
    #[serde(rename = "spacing")]
    Spacing { amount: f64 },
    #[serde(rename = "world_text")]
    WorldText {
        world_x: f64,
        world_y: f64,
        world_z: f64,
        text: String,
        color: [f64; 4],
        lifetime: f64,
        max_lifetime: f64,
    },
    #[serde(rename = "screen_flash")]
    ScreenFlash { color: [f64; 4] },
}

fn to_border(b: &Option<(Vec<f64>, f64)>) -> Option<([f32; 4], f32)> {
    let (c, w) = b.as_ref()?;
    if c.len() < 4 {
        return None;
    }
    Some((
        [
            c[0] as f32,
            c[1] as f32,
            c[2] as f32,
            c[3] as f32,
        ],
        *w as f32,
    ))
}

#[derive(Deserialize)]
struct MeshDefMsg {
    name: String,
    vertices: Vec<VertexWire>,
    indices: Vec<u32>,
}

impl MeshDefMsg {
    fn to_mesh_def(&self) -> MeshDef {
        MeshDef {
            name: self.name.clone(),
            vertices: self.vertices.iter().map(VertexWire::to_mesh_vertex).collect(),
            indices: self.indices.clone(),
        }
    }
}

fn f64_4(c: [f64; 4]) -> [f32; 4] {
    [c[0] as f32, c[1] as f32, c[2] as f32, c[3] as f32]
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
        other => {
            log::warn!(
                "UiAnchor: unknown '{}', defaulting to TopLeft. Add to messagepack-schema.md if valid.",
                other
            );
            UiAnchor::TopLeft
        }
    }
}

fn ui_size_from_wire(s: &UiSizeWire) -> UiSize {
    match s {
        UiSizeWire::Wrap(_) => UiSize::WrapContent,
        UiSizeWire::Fixed([w, h]) => UiSize::Fixed(*w as f32, *h as f32),
    }
}

fn ui_rect_from_msg(m: &UiRectMsg) -> UiRect {
    UiRect {
        anchor: ui_anchor_from_str(&m.anchor),
        offset: [m.offset[0] as f32, m.offset[1] as f32],
        size: ui_size_from_wire(&m.size),
    }
}

fn ui_component_from_msg(m: &UiComponentMsg) -> UiComponent {
    match m {
        UiComponentMsg::VerticalLayout { spacing, padding } => UiComponent::VerticalLayout {
            spacing: *spacing as f32,
            padding: [
                padding[0] as f32,
                padding[1] as f32,
                padding[2] as f32,
                padding[3] as f32,
            ],
        },
        UiComponentMsg::HorizontalLayout { spacing, padding } => UiComponent::HorizontalLayout {
            spacing: *spacing as f32,
            padding: [
                padding[0] as f32,
                padding[1] as f32,
                padding[2] as f32,
                padding[3] as f32,
            ],
        },
        UiComponentMsg::Separator => UiComponent::Separator,
        UiComponentMsg::Rect {
            color,
            corner_radius,
            border,
        } => UiComponent::Rect {
            color: f64_4(*color),
            corner_radius: *corner_radius as f32,
            border: to_border(border),
        },
        UiComponentMsg::Text { text, color, size, bold } => UiComponent::Text {
            text: text.clone(),
            color: f64_4(*color),
            size: *size as f32,
            bold: *bold,
        },
        UiComponentMsg::Button {
            label,
            action,
            color,
            min_width,
            min_height,
        } => UiComponent::Button {
            label: label.clone(),
            action: action.clone(),
            color: f64_4(*color),
            min_width: *min_width as f32,
            min_height: *min_height as f32,
        },
        UiComponentMsg::ProgressBar {
            value,
            max,
            width,
            height,
            fg_color_high,
            fg_color_mid,
            fg_color_low,
            bg_color,
            corner_radius,
        } => UiComponent::ProgressBar {
            value: *value as f32,
            max: *max as f32,
            width: *width as f32,
            height: *height as f32,
            fg_color_high: f64_4(*fg_color_high),
            fg_color_mid: f64_4(*fg_color_mid),
            fg_color_low: f64_4(*fg_color_low),
            bg_color: f64_4(*bg_color),
            corner_radius: *corner_radius as f32,
        },
        UiComponentMsg::Spacing { amount } => UiComponent::Spacing {
            amount: *amount as f32,
        },
        UiComponentMsg::WorldText {
            world_x,
            world_y,
            world_z,
            text,
            color,
            lifetime,
            max_lifetime,
        } => UiComponent::WorldText {
            world_x: *world_x as f32,
            world_y: *world_y as f32,
            world_z: *world_z as f32,
            text: text.clone(),
            color: f64_4(*color),
            lifetime: *lifetime as f32,
            max_lifetime: *max_lifetime as f32,
        },
        UiComponentMsg::ScreenFlash { color } => UiComponent::ScreenFlash {
            color: f64_4(*color),
        },
    }
}

fn ui_node_from_msg(m: &UiNodeMsg) -> UiNode {
    UiNode {
        rect: ui_rect_from_msg(&m.rect),
        component: ui_component_from_msg(&m.component),
        children: m.children.iter().map(ui_node_from_msg).collect(),
    }
}

fn draw_command_from_msg(m: &DrawCommandMsg) -> DrawCommand {
    match m {
        DrawCommandMsg::PlayerSprite { x, y, frame } => DrawCommand::PlayerSprite {
            x: *x as f32,
            y: *y as f32,
            frame: *frame,
        },
        DrawCommandMsg::SpriteRaw {
            x,
            y,
            width,
            height,
            uv_offset,
            uv_size,
            color_tint,
        } => DrawCommand::SpriteRaw {
            x: *x as f32,
            y: *y as f32,
            width: *width as f32,
            height: *height as f32,
            uv_offset: [uv_offset[0] as f32, uv_offset[1] as f32],
            uv_size: [uv_size[0] as f32, uv_size[1] as f32],
            color_tint: f64_4(*color_tint),
        },
        DrawCommandMsg::Particle { x, y, r, g, b, alpha, size } => DrawCommand::Particle {
            x: *x as f32,
            y: *y as f32,
            r: *r as f32,
            g: *g as f32,
            b: *b as f32,
            alpha: *alpha as f32,
            size: *size as f32,
        },
        DrawCommandMsg::Item { x, y, kind } => DrawCommand::Item {
            x: *x as f32,
            y: *y as f32,
            kind: *kind,
        },
        DrawCommandMsg::Obstacle { x, y, radius, kind } => DrawCommand::Obstacle {
            x: *x as f32,
            y: *y as f32,
            radius: *radius as f32,
            kind: *kind,
        },
        DrawCommandMsg::Box3D {
            x,
            y,
            z,
            half_w,
            half_h,
            half_d,
            color,
        } => DrawCommand::Box3D {
            x: *x as f32,
            y: *y as f32,
            z: *z as f32,
            half_w: *half_w as f32,
            half_h: *half_h as f32,
            half_d: *half_d as f32,
            color: f64_4(*color),
        },
        DrawCommandMsg::GridPlane { size, divisions, color } => DrawCommand::GridPlane {
            size: *size as f32,
            divisions: *divisions,
            color: f64_4(*color),
        },
        DrawCommandMsg::GridPlaneVerts { vertices } => DrawCommand::GridPlaneVerts {
            vertices: vertices.iter().map(VertexWire::to_mesh_vertex).collect(),
        },
        DrawCommandMsg::Skybox { top_color, bottom_color } => DrawCommand::Skybox {
            top_color: f64_4(*top_color),
            bottom_color: f64_4(*bottom_color),
        },
    }
}

fn camera_from_msg(m: &CameraMsg) -> CameraParams {
    match m {
        CameraMsg::Camera2D { offset_x, offset_y } => CameraParams::Camera2D {
            offset_x: *offset_x as f32,
            offset_y: *offset_y as f32,
        },
        CameraMsg::Camera3D {
            eye,
            target,
            up,
            fov_deg,
            near,
            far,
        } => CameraParams::Camera3D {
            eye: [eye[0] as f32, eye[1] as f32, eye[2] as f32],
            target: [target[0] as f32, target[1] as f32, target[2] as f32],
            up: [up[0] as f32, up[1] as f32, up[2] as f32],
            fov_deg: *fov_deg as f32,
            near: *near as f32,
            far: *far as f32,
        },
    }
}

/// MessagePack バイナリをデコードして RenderFrame を構築する。
pub fn decode_render_frame_from_msgpack(
    bytes: &[u8],
    cursor_grab: Option<bool>,
) -> Result<RenderFrame, rmp_serde::decode::Error> {
    let frame: FrameMsg = from_slice(bytes)?;
    Ok(RenderFrame {
        commands: frame.commands.iter().map(draw_command_from_msg).collect(),
        camera: camera_from_msg(&frame.camera),
        ui: UiCanvas {
            nodes: frame.ui.nodes.iter().map(ui_node_from_msg).collect(),
        },
        cursor_grab,
        mesh_definitions: frame
            .mesh_definitions
            .iter()
            .map(MeshDefMsg::to_mesh_def)
            .collect(),
    })
}
