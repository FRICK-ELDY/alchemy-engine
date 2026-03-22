//! Erlang term (ETF) バイナリ → RenderFrame 変換
//!
//! スキーマ: docs/architecture/erlang-term-schema.md
//! Elixir の :erlang.term_to_binary 出力を eetf でデコードする。

use eetf::{List, Map, Term};
use num_traits::cast::ToPrimitive;
use render::{
    CameraParams, DrawCommand, MeshDef, MeshVertex, RenderFrame, UiAnchor, UiCanvas, UiComponent,
    UiNode, UiRect, UiSize,
};
use std::io::Cursor;

fn map_get<'a>(map: &'a Map, key: &str) -> Option<&'a Term> {
    for (k, v) in &map.map {
        if term_to_str(k).as_deref() == Some(key) {
            return Some(v);
        }
    }
    None
}

fn term_to_str(t: &Term) -> Option<String> {
    match t {
        Term::Atom(a) => Some(a.name.clone()),
        Term::Binary(b) => String::from_utf8(b.bytes.clone()).ok(),
        Term::ByteList(bl) => String::from_utf8(bl.bytes.clone()).ok(),
        _ => None,
    }
}

fn term_to_f64(t: &Term) -> Option<f64> {
    t.to_f64()
}

fn term_to_u32(t: &Term) -> Option<u32> {
    t.to_u32()
}

fn term_to_u8(t: &Term) -> Option<u8> {
    t.to_u8()
}

fn term_to_bool(t: &Term) -> Option<bool> {
    t.to_u8().map(|u| u != 0)
}

fn get_map(t: &Term) -> Option<&Map> {
    match t {
        Term::Map(m) => Some(m),
        _ => None,
    }
}

fn get_vec<'a>(t: &'a Term) -> Option<Vec<&'a Term>> {
    match t {
        Term::List(l) => Some(l.elements.iter().collect()),
        _ => None,
    }
}

fn get_tag(map: &Map) -> Option<String> {
    map_get(map, "t").and_then(term_to_str)
}

fn f64_4(c: &[f64]) -> [f32; 4] {
    [
        c.get(0).copied().unwrap_or(0.0) as f32,
        c.get(1).copied().unwrap_or(0.0) as f32,
        c.get(2).copied().unwrap_or(0.0) as f32,
        c.get(3).copied().unwrap_or(1.0) as f32,
    ]
}

fn arr_f64(t: &Term) -> Vec<f64> {
    get_vec(t)
        .map(|v| {
            v.iter()
                .filter_map(|x| term_to_f64(x))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn parse_draw_command(map: &Map) -> Option<DrawCommand> {
    let tag = get_tag(map)?;
    Some(match tag.as_str() {
        "player_sprite" => {
            let x = map_get(map, "x").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let y = map_get(map, "y").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let frame = map_get(map, "frame").and_then(term_to_u8).unwrap_or(0);
            DrawCommand::PlayerSprite { x, y, frame }
        }
        "sprite_raw" => {
            let x = map_get(map, "x").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let y = map_get(map, "y").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let width = map_get(map, "width").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let height = map_get(map, "height").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let uv_offset = arr_f64(map_get(map, "uv_offset").unwrap_or(&Term::from(List::nil())));
            let uv_size = arr_f64(map_get(map, "uv_size").unwrap_or(&Term::from(List::nil())));
            let color_tint = arr_f64(map_get(map, "color_tint").unwrap_or(&Term::from(List::nil())));
            DrawCommand::SpriteRaw {
                x,
                y,
                width,
                height,
                uv_offset: [uv_offset.get(0).copied().unwrap_or(0.0) as f32, uv_offset.get(1).copied().unwrap_or(0.0) as f32],
                uv_size: [uv_size.get(0).copied().unwrap_or(0.0) as f32, uv_size.get(1).copied().unwrap_or(0.0) as f32],
                color_tint: f64_4(&color_tint),
            }
        }
        "particle" => {
            let x = map_get(map, "x").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let y = map_get(map, "y").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let r = map_get(map, "r").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let g = map_get(map, "g").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let b = map_get(map, "b").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let alpha = map_get(map, "alpha").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let size = map_get(map, "size").and_then(term_to_f64).unwrap_or(0.0) as f32;
            DrawCommand::Particle {
                x, y, r, g, b, alpha, size,
            }
        }
        "item" => {
            let x = map_get(map, "x").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let y = map_get(map, "y").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let kind = map_get(map, "kind").and_then(term_to_u8).unwrap_or(0);
            DrawCommand::Item { x, y, kind }
        }
        "obstacle" => {
            let x = map_get(map, "x").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let y = map_get(map, "y").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let radius = map_get(map, "radius").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let kind = map_get(map, "kind").and_then(term_to_u8).unwrap_or(0);
            DrawCommand::Obstacle {
                x, y, radius, kind,
            }
        }
        "box_3d" => {
            let x = map_get(map, "x").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let y = map_get(map, "y").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let z = map_get(map, "z").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let half_w = map_get(map, "half_w").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let half_h = map_get(map, "half_h").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let half_d = map_get(map, "half_d").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let color = arr_f64(map_get(map, "color").unwrap_or(&Term::from(List::nil())));
            DrawCommand::Box3D {
                x, y, z,
                half_w, half_h, half_d,
                color: f64_4(&color),
            }
        }
        "grid_plane" => {
            let size = map_get(map, "size").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let divisions = map_get(map, "divisions").and_then(term_to_u32).unwrap_or(0);
            let color = arr_f64(map_get(map, "color").unwrap_or(&Term::from(List::nil())));
            DrawCommand::GridPlane {
                size, divisions, color: f64_4(&color),
            }
        }
        "grid_plane_verts" => {
            let vertices: Vec<MeshVertex> = get_vec(map_get(map, "vertices")?)
                .unwrap_or_default()
                .iter()
                .filter_map(|v| {
                    let arr = get_vec(v)?;
                    let p = arr.get(0).and_then(|x| get_vec(x)).unwrap_or_default();
                    let c = arr.get(1).and_then(|x| get_vec(x)).unwrap_or_default();
                    let p: Vec<f32> = p.iter().take(3).filter_map(|x| term_to_f64(x).map(|f| f as f32)).collect();
                    let c: Vec<f32> = c.iter().take(4).filter_map(|x| term_to_f64(x).map(|f| f as f32)).collect();
                    Some(MeshVertex {
                        position: [p.get(0).copied().unwrap_or(0.0), p.get(1).copied().unwrap_or(0.0), p.get(2).copied().unwrap_or(0.0)],
                        color: [c.get(0).copied().unwrap_or(0.0), c.get(1).copied().unwrap_or(0.0), c.get(2).copied().unwrap_or(0.0), c.get(3).copied().unwrap_or(1.0)],
                    })
                })
                .collect();
            DrawCommand::GridPlaneVerts { vertices }
        }
        "skybox" => {
            let top = arr_f64(map_get(map, "top_color").unwrap_or(&Term::from(List::nil())));
            let bottom = arr_f64(map_get(map, "bottom_color").unwrap_or(&Term::from(List::nil())));
            DrawCommand::Skybox {
                top_color: f64_4(&top),
                bottom_color: f64_4(&bottom),
            }
        }
        _ => return None,
    })
}

fn parse_camera(map: &Map) -> CameraParams {
    let tag = get_tag(map).unwrap_or_default();
    match tag.as_str() {
        "camera_2d" => {
            let offset_x = map_get(map, "offset_x").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let offset_y = map_get(map, "offset_y").and_then(term_to_f64).unwrap_or(0.0) as f32;
            CameraParams::Camera2D { offset_x, offset_y }
        }
        "camera_3d" => {
            let eye = arr_f64(map_get(map, "eye").unwrap_or(&Term::from(List::nil())));
            let target = arr_f64(map_get(map, "target").unwrap_or(&Term::from(List::nil())));
            let up = arr_f64(map_get(map, "up").unwrap_or(&Term::from(List::nil())));
            let fov_deg = map_get(map, "fov_deg").and_then(term_to_f64).unwrap_or(60.0) as f32;
            let near = map_get(map, "near").and_then(term_to_f64).unwrap_or(0.1) as f32;
            let far = map_get(map, "far").and_then(term_to_f64).unwrap_or(1000.0) as f32;
            CameraParams::Camera3D {
                eye: [eye.get(0).copied().unwrap_or(0.0) as f32, eye.get(1).copied().unwrap_or(0.0) as f32, eye.get(2).copied().unwrap_or(0.0) as f32],
                target: [target.get(0).copied().unwrap_or(0.0) as f32, target.get(1).copied().unwrap_or(0.0) as f32, target.get(2).copied().unwrap_or(0.0) as f32],
                up: [up.get(0).copied().unwrap_or(0.0) as f32, up.get(1).copied().unwrap_or(1.0) as f32, up.get(2).copied().unwrap_or(0.0) as f32],
                fov_deg, near, far,
            }
        }
        _ => CameraParams::Camera2D {
            offset_x: 0.0,
            offset_y: 0.0,
        },
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

fn parse_ui_rect(map: Option<&Map>) -> UiRect {
    let empty_map = Map {
        map: std::collections::HashMap::new(),
    };
    let map = map.unwrap_or(&empty_map);
    let anchor = map_get(map, "anchor").and_then(term_to_str).unwrap_or_else(|| "top_left".into());
    let offset = arr_f64(map_get(map, "offset").unwrap_or(&Term::from(List::nil())));
    let size_term = map_get(map, "size");
    let size = match size_term.and_then(term_to_str) {
        Some(s) if s == "wrap" => UiSize::WrapContent,
        _ => {
            let arr = size_term.map(arr_f64).unwrap_or_default();
            UiSize::Fixed(arr.get(0).copied().unwrap_or(0.0) as f32, arr.get(1).copied().unwrap_or(0.0) as f32)
        }
    };
    UiRect {
        anchor: ui_anchor_from_str(&anchor),
        offset: [offset.get(0).copied().unwrap_or(0.0) as f32, offset.get(1).copied().unwrap_or(0.0) as f32],
        size,
    }
}

fn parse_ui_component(map: Option<&Map>) -> UiComponent {
    let empty_map = Map {
        map: std::collections::HashMap::new(),
    };
    let map = map.unwrap_or(&empty_map);
    let tag = get_tag(map).unwrap_or_default();
    match tag.as_str() {
        "separator" => UiComponent::Separator,
        "vertical_layout" => {
            let spacing = map_get(map, "spacing").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let padding = arr_f64(map_get(map, "padding").unwrap_or(&Term::from(List::nil())));
            UiComponent::VerticalLayout {
                spacing,
                padding: [
                    padding.get(0).copied().unwrap_or(0.0) as f32,
                    padding.get(1).copied().unwrap_or(0.0) as f32,
                    padding.get(2).copied().unwrap_or(0.0) as f32,
                    padding.get(3).copied().unwrap_or(0.0) as f32,
                ],
            }
        }
        "horizontal_layout" => {
            let spacing = map_get(map, "spacing").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let padding = arr_f64(map_get(map, "padding").unwrap_or(&Term::from(List::nil())));
            UiComponent::HorizontalLayout {
                spacing,
                padding: [
                    padding.get(0).copied().unwrap_or(0.0) as f32,
                    padding.get(1).copied().unwrap_or(0.0) as f32,
                    padding.get(2).copied().unwrap_or(0.0) as f32,
                    padding.get(3).copied().unwrap_or(0.0) as f32,
                ],
            }
        }
        "rect" => {
            let color = arr_f64(map_get(map, "color").unwrap_or(&Term::from(List::nil())));
            let corner_radius = map_get(map, "corner_radius").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let border = None; // TODO: parse border if needed
            UiComponent::Rect {
                color: f64_4(&color),
                corner_radius,
                border,
            }
        }
        "text" => {
            let text = map_get(map, "text").and_then(term_to_str).unwrap_or_default();
            let color = arr_f64(map_get(map, "color").unwrap_or(&Term::from(List::nil())));
            let size = map_get(map, "size").and_then(term_to_f64).unwrap_or(14.0) as f32;
            let bold = map_get(map, "bold").and_then(term_to_bool).unwrap_or(false);
            UiComponent::Text {
                text, color: f64_4(&color), size, bold,
            }
        }
        "button" => {
            let label = map_get(map, "label").and_then(term_to_str).unwrap_or_default();
            let action = map_get(map, "action").and_then(term_to_str).unwrap_or_default();
            let color = arr_f64(map_get(map, "color").unwrap_or(&Term::from(List::nil())));
            let min_width = map_get(map, "min_width").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let min_height = map_get(map, "min_height").and_then(term_to_f64).unwrap_or(0.0) as f32;
            UiComponent::Button {
                label, action, color: f64_4(&color), min_width, min_height,
            }
        }
        "progress_bar" => {
            let value = map_get(map, "value").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let max = map_get(map, "max").and_then(term_to_f64).unwrap_or(1.0) as f32;
            let width = map_get(map, "width").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let height = map_get(map, "height").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let fg_color_high = arr_f64(map_get(map, "fg_color_high").unwrap_or(&Term::from(List::nil())));
            let fg_color_mid = arr_f64(map_get(map, "fg_color_mid").unwrap_or(&Term::from(List::nil())));
            let fg_color_low = arr_f64(map_get(map, "fg_color_low").unwrap_or(&Term::from(List::nil())));
            let bg_color = arr_f64(map_get(map, "bg_color").unwrap_or(&Term::from(List::nil())));
            let corner_radius = map_get(map, "corner_radius").and_then(term_to_f64).unwrap_or(0.0) as f32;
            UiComponent::ProgressBar {
                value, max, width, height,
                fg_color_high: f64_4(&fg_color_high),
                fg_color_mid: f64_4(&fg_color_mid),
                fg_color_low: f64_4(&fg_color_low),
                bg_color: f64_4(&bg_color),
                corner_radius,
            }
        }
        "spacing" => {
            let amount = map_get(map, "amount").and_then(term_to_f64).unwrap_or(0.0) as f32;
            UiComponent::Spacing { amount }
        }
        "world_text" => {
            let world_x = map_get(map, "world_x").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let world_y = map_get(map, "world_y").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let world_z = map_get(map, "world_z").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let text = map_get(map, "text").and_then(term_to_str).unwrap_or_default();
            let color = arr_f64(map_get(map, "color").unwrap_or(&Term::from(List::nil())));
            let lifetime = map_get(map, "lifetime").and_then(term_to_f64).unwrap_or(0.0) as f32;
            let max_lifetime = map_get(map, "max_lifetime").and_then(term_to_f64).unwrap_or(1.0) as f32;
            UiComponent::WorldText {
                world_x, world_y, world_z, text,
                color: f64_4(&color),
                lifetime, max_lifetime,
            }
        }
        "screen_flash" => {
            let color = arr_f64(map_get(map, "color").unwrap_or(&Term::from(List::nil())));
            UiComponent::ScreenFlash { color: f64_4(&color) }
        }
        _ => UiComponent::Separator,
    }
}

fn parse_ui_node(term: &Term) -> UiNode {
    let map = get_map(term);
    let rect = parse_ui_rect(map.and_then(|m| map_get(m, "rect").and_then(get_map)));
    let component = parse_ui_component(map.and_then(|m| map_get(m, "component").and_then(get_map)));
    let empty_list = Term::from(List::nil());
    let children_term = map.and_then(|m| map_get(m, "children")).unwrap_or(&empty_list);
    let children: Vec<UiNode> = get_vec(children_term)
        .unwrap_or_default()
        .iter()
        .map(|t| parse_ui_node(t))
        .collect();
    UiNode {
        rect,
        component,
        children,
    }
}

fn parse_mesh_def(map: &Map) -> MeshDef {
    let name = map_get(map, "name").and_then(term_to_str).unwrap_or_default();
    let vertices: Vec<MeshVertex> = get_vec(map_get(map, "vertices").unwrap_or(&Term::from(List::nil())))
        .unwrap_or_default()
        .iter()
        .filter_map(|v| {
            let arr = get_vec(v)?;
            let p = arr.get(0).and_then(|x| get_vec(x)).unwrap_or_default();
            let c = arr.get(1).and_then(|x| get_vec(x)).unwrap_or_default();
            let p: Vec<f32> = p.iter().take(3).filter_map(|x| term_to_f64(x).map(|f| f as f32)).collect();
            let c: Vec<f32> = c.iter().take(4).filter_map(|x| term_to_f64(x).map(|f| f as f32)).collect();
            Some(MeshVertex {
                position: [p.get(0).copied().unwrap_or(0.0), p.get(1).copied().unwrap_or(0.0), p.get(2).copied().unwrap_or(0.0)],
                color: [c.get(0).copied().unwrap_or(0.0), c.get(1).copied().unwrap_or(0.0), c.get(2).copied().unwrap_or(0.0), c.get(3).copied().unwrap_or(1.0)],
            })
        })
        .collect();
    let indices: Vec<u32> = get_vec(map_get(map, "indices").unwrap_or(&Term::from(List::nil())))
        .unwrap_or_default()
        .iter()
        .filter_map(|x| term_to_u32(x))
        .collect();
    MeshDef { name, vertices, indices }
}

fn parse_cursor_grab(s: &str) -> Option<bool> {
    match s {
        "grab" => Some(true),
        "release" => Some(false),
        _ => None,
    }
}

/// Erlang term バイナリをデコードして RenderFrame を構築する。
pub fn decode_render_frame(bytes: &[u8]) -> Result<RenderFrame, eetf::DecodeError> {
    let term = Term::decode(Cursor::new(bytes))?;
    let map = get_map(&term).ok_or_else(|| {
        eetf::DecodeError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "expected map",
        ))
    })?;

    let commands: Vec<DrawCommand> = get_vec(map_get(map, "commands").unwrap_or(&Term::from(List::nil())))
        .unwrap_or_default()
        .iter()
        .filter_map(|t| get_map(t).and_then(parse_draw_command))
        .collect();

    let camera = map_get(map, "camera")
        .and_then(|t| get_map(t))
        .map(parse_camera)
        .unwrap_or(CameraParams::Camera2D {
            offset_x: 0.0,
            offset_y: 0.0,
        });

    let empty_list = Term::from(List::nil());
    let ui_map = map_get(map, "ui").and_then(get_map);
    let ui_nodes_term = ui_map
        .and_then(|m| map_get(m, "nodes"))
        .unwrap_or(&empty_list);
    let ui_nodes: Vec<UiNode> = get_vec(ui_nodes_term)
        .unwrap_or_default()
        .iter()
        .map(|t| parse_ui_node(t))
        .collect();

    let mesh_definitions: Vec<MeshDef> = get_vec(map_get(map, "mesh_definitions").unwrap_or(&Term::from(List::nil())))
        .unwrap_or_default()
        .iter()
        .filter_map(|t| get_map(t).map(parse_mesh_def))
        .collect();

    let cursor_grab = map_get(map, "cursor_grab")
        .and_then(term_to_str)
        .as_deref()
        .and_then(parse_cursor_grab);

    Ok(RenderFrame {
        commands,
        camera,
        ui: UiCanvas { nodes: ui_nodes },
        cursor_grab,
        mesh_definitions,
    })
}
