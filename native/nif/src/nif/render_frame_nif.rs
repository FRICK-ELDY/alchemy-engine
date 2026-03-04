//! Path: native/game_nif/src/nif/render_frame_nif.rs
//! Summary: RenderFrameBuffer 作成・push_render_frame NIF
//!
//! Phase R-2: Elixir 側（game_content）が DrawCommand リストを組み立てて
//! push_render_frame NIF 経由でバッファに書き込む。

use crate::render_frame_buffer::RenderFrameBuffer;
use render::{
    CameraParams, DrawCommand, RenderFrame, UiAnchor, UiCanvas, UiComponent, UiNode, UiRect, UiSize,
};
use rustler::types::list::ListIterator;
use rustler::types::tuple::get_tuple;
use rustler::{Atom, Error as NifError, NifResult, ResourceArc, Term};

use crate::ok;

// ── リソース作成 ──────────────────────────────────────────────────────

#[rustler::nif]
pub fn create_render_frame_buffer() -> ResourceArc<RenderFrameBuffer> {
    ResourceArc::new(RenderFrameBuffer::new())
}

// ── push_render_frame ────────────────────────────────────────────────

/// Elixir 側から DrawCommand リスト・カメラ・UiCanvas を受け取り、
/// RenderFrameBuffer に書き込む。
///
/// ## DrawCommand タプル形式
/// - `{:player_sprite, x, y, frame}`
/// - `{:sprite, x, y, kind_id, frame}`
/// - `{:particle, x, y, r, g, b, {alpha, size}}`
/// - `{:item, x, y, kind}`
/// - `{:obstacle, x, y, radius, kind}`
///
/// ## CameraParams タプル形式
/// - `{:camera_2d, offset_x, offset_y}`
///
/// ## UiCanvas タプル形式
/// `{:canvas, [node]}`
///
/// ### UiNode タプル形式
/// `{:node, rect, component, [children]}`
///
/// ### UiRect タプル形式
/// `{anchor_atom, {offset_x, offset_y}, size}`
/// - `anchor_atom`: `:top_left` | `:top_center` | `:top_right` |
///                  `:middle_left` | `:center` | `:middle_right` |
///                  `:bottom_left` | `:bottom_center` | `:bottom_right`
/// - `size`: `{:fixed, w, h}` | `:wrap`
///
/// ### UiComponent タプル形式
/// - `{:vertical_layout, spacing, {pad_left, pad_top, pad_right, pad_bottom}}`
/// - `{:horizontal_layout, spacing, {pad_left, pad_top, pad_right, pad_bottom}}`
/// - `{:rect, {r,g,b,a}, corner_radius, border}`
///   - `border`: `:none` | `{{r,g,b,a}, width}`
/// - `{:text, text, {r,g,b,a}, size, bold}`
/// - `{:button, label, action, {r,g,b,a}, min_width, min_height}`
/// - `{:progress_bar, value, max, width, height, {fg_high, fg_mid, fg_low, bg, corner_radius}}`
///   - 各色は `{r,g,b,a}`、末尾5要素は内部タプルにまとめる（Rustler の7要素制約のため）
/// - `:separator`
/// - `{:spacing, amount}`
/// - `{:world_text, world_x, world_y, world_z, text, {r,g,b,a}, {lifetime, max_lifetime}}`
/// - `{:screen_flash, {r,g,b,a}}`
#[rustler::nif]
pub fn push_render_frame(
    buf: ResourceArc<RenderFrameBuffer>,
    commands: Term,
    camera: Term,
    ui: Term,
    cursor_grab: Term,
) -> NifResult<Atom> {
    let commands = decode_commands(commands)?;
    let camera = decode_camera(camera)?;
    let ui = decode_ui_canvas(ui)?;
    let cursor_grab = decode_cursor_grab(cursor_grab)?;

    buf.push(RenderFrame {
        commands,
        camera,
        ui,
        cursor_grab,
    });

    Ok(ok())
}

// ── デコードヘルパー ──────────────────────────────────────────────────

fn decode_commands(term: Term) -> NifResult<Vec<DrawCommand>> {
    let iter: ListIterator = term.decode()?;
    iter.map(decode_command).collect()
}

fn atom_str<'a>(term: Term<'a>) -> NifResult<String> {
    term.atom_to_string()
        .map_err(|_| NifError::Term(Box::new("expected atom")))
}

/// タプルの先頭要素（タグアトム）を文字列として取得する。
fn tag_of(term: Term) -> NifResult<String> {
    let elems = get_tuple(term).map_err(|_| NifError::Term(Box::new("expected tuple")))?;
    let first = elems
        .first()
        .ok_or_else(|| NifError::Term(Box::new("expected non-empty tuple")))?;
    atom_str(*first)
}

fn decode_command(term: Term) -> NifResult<DrawCommand> {
    let tag = tag_of(term)?;

    match tag.as_str() {
        // {:player_sprite, x, y, frame}
        "player_sprite" => {
            let (_, x, y, frame): (Atom, f64, f64, u32) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "player_sprite: expected {:player_sprite, x, y, frame}",
                ))
            })?;
            Ok(DrawCommand::PlayerSprite {
                x: x as f32,
                y: y as f32,
                frame: frame as u8,
            })
        }
        // {:sprite, x, y, kind_id, frame}
        "sprite" => {
            let (_, x, y, kind_id, frame): (Atom, f64, f64, u32, u32) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new("sprite: expected {:sprite, x, y, kind_id, frame}"))
                })?;
            Ok(DrawCommand::Sprite {
                x: x as f32,
                y: y as f32,
                kind_id: kind_id as u8,
                frame: frame as u8,
            })
        }
        // {:particle, x, y, r, g, b, {alpha, size}}
        "particle" => {
            let (_, x, y, r, g, b, (alpha, size)): (Atom, f64, f64, f64, f64, f64, (f64, f64)) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "particle: expected {:particle, x, y, r, g, b, {alpha, size}}",
                    ))
                })?;
            Ok(DrawCommand::Particle {
                x: x as f32,
                y: y as f32,
                r: r as f32,
                g: g as f32,
                b: b as f32,
                alpha: alpha as f32,
                size: size as f32,
            })
        }
        // {:item, x, y, kind}
        "item" => {
            let (_, x, y, kind): (Atom, f64, f64, u32) = term
                .decode()
                .map_err(|_| NifError::Term(Box::new("item: expected {:item, x, y, kind}")))?;
            Ok(DrawCommand::Item {
                x: x as f32,
                y: y as f32,
                kind: kind as u8,
            })
        }
        // {:obstacle, x, y, radius, kind}
        "obstacle" => {
            let (_, x, y, radius, kind): (Atom, f64, f64, f64, u32) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "obstacle: expected {:obstacle, x, y, radius, kind}",
                    ))
                })?;
            Ok(DrawCommand::Obstacle {
                x: x as f32,
                y: y as f32,
                radius: radius as f32,
                kind: kind as u8,
            })
        }
        // {:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}
        "box_3d" => {
            #[allow(clippy::type_complexity)]
            let (_, x, y, z, half_w, half_h, (half_d, r, g, b, a)): (
                Atom,
                f64,
                f64,
                f64,
                f64,
                f64,
                (f64, f64, f64, f64, f64),
            ) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "box_3d: expected {:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}",
                ))
            })?;
            Ok(DrawCommand::Box3D {
                x: x as f32,
                y: y as f32,
                z: z as f32,
                half_w: half_w as f32,
                half_h: half_h as f32,
                half_d: half_d as f32,
                color: [r as f32, g as f32, b as f32, a as f32],
            })
        }
        // {:grid_plane, size, divisions, {r, g, b, a}}
        "grid_plane" => {
            let (_, size, divisions, color): (Atom, f64, u32, (f64, f64, f64, f64)) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "grid_plane: expected {:grid_plane, size, divisions, {r, g, b, a}}",
                    ))
                })?;
            Ok(DrawCommand::GridPlane {
                size: size as f32,
                divisions,
                color: [
                    color.0 as f32,
                    color.1 as f32,
                    color.2 as f32,
                    color.3 as f32,
                ],
            })
        }
        // {:skybox, {top_r, top_g, top_b, top_a}, {bot_r, bot_g, bot_b, bot_a}}
        "skybox" => {
            #[allow(clippy::type_complexity)]
            let (_, top, bot): (Atom, (f64, f64, f64, f64), (f64, f64, f64, f64)) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new("skybox: expected {:skybox, {r,g,b,a}, {r,g,b,a}}"))
                })?;
            Ok(DrawCommand::Skybox {
                top_color: [top.0 as f32, top.1 as f32, top.2 as f32, top.3 as f32],
                bottom_color: [bot.0 as f32, bot.1 as f32, bot.2 as f32, bot.3 as f32],
            })
        }
        // {:sprite_raw, x, y, width, height, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}
        "sprite_raw" => {
            let (_, x, y, width, height, uvs_t): (Atom, f64, f64, f64, f64, Term) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "sprite_raw: expected {:sprite_raw, x, y, width, height, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}",
                    ))
                })?;
            let (uv_offset_t, uv_size_t, color_t): (Term, Term, Term) =
                uvs_t.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "sprite_raw: uvs expected {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}",
                    ))
                })?;
            let (uv_ox, uv_oy): (f64, f64) = uv_offset_t
                .decode()
                .map_err(|_| NifError::Term(Box::new("sprite_raw: uv_offset expected {f, f}")))?;
            let (uv_sx, uv_sy): (f64, f64) = uv_size_t
                .decode()
                .map_err(|_| NifError::Term(Box::new("sprite_raw: uv_size expected {f, f}")))?;
            let color = decode_color(color_t)?;
            Ok(DrawCommand::SpriteRaw {
                x: x as f32,
                y: y as f32,
                width: width as f32,
                height: height as f32,
                uv_offset: [uv_ox as f32, uv_oy as f32],
                uv_size: [uv_sx as f32, uv_sy as f32],
                color_tint: color,
            })
        }
        other => Err(NifError::Term(Box::new(format!(
            "DrawCommand: unknown tag '{other}'"
        )))),
    }
}

fn decode_camera(term: Term) -> NifResult<CameraParams> {
    let tag_str = tag_of(term)?;

    match tag_str.as_str() {
        // {:camera_2d, offset_x, offset_y}
        "camera_2d" => {
            let (_, offset_x, offset_y): (Atom, f64, f64) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "CameraParams: expected {:camera_2d, offset_x, offset_y}",
                ))
            })?;
            Ok(CameraParams::Camera2D {
                offset_x: offset_x as f32,
                offset_y: offset_y as f32,
            })
        }
        // {:camera_3d, {eye_x, eye_y, eye_z}, {target_x, target_y, target_z}, {up_x, up_y, up_z}, {fov_deg, near, far}}
        "camera_3d" => {
            #[allow(clippy::type_complexity)]
            let (_, eye, target, up, (fov_deg, near, far)): (
                Atom,
                (f64, f64, f64),
                (f64, f64, f64),
                (f64, f64, f64),
                (f64, f64, f64),
            ) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "CameraParams: expected {:camera_3d, {ex,ey,ez}, {tx,ty,tz}, {ux,uy,uz}, {fov,near,far}}",
                ))
            })?;
            Ok(CameraParams::Camera3D {
                eye: [eye.0 as f32, eye.1 as f32, eye.2 as f32],
                target: [target.0 as f32, target.1 as f32, target.2 as f32],
                up: [up.0 as f32, up.1 as f32, up.2 as f32],
                fov_deg: fov_deg as f32,
                near: near as f32,
                far: far as f32,
            })
        }
        other => Err(NifError::Term(Box::new(format!(
            "CameraParams: unknown tag '{other}'"
        )))),
    }
}

// ── UiCanvas デコード ─────────────────────────────────────────────────

/// UiCanvas をデコードする。
/// Elixir 側の形式: `{:canvas, [node]}`
fn decode_ui_canvas(term: Term) -> NifResult<UiCanvas> {
    let tag = tag_of(term)?;
    if tag != "canvas" {
        return Err(NifError::Term(Box::new(format!(
            "UiCanvas: expected :canvas tag, got '{tag}'"
        ))));
    }

    let (_, nodes_term): (Atom, Term) = term
        .decode()
        .map_err(|_| NifError::Term(Box::new("UiCanvas: expected {:canvas, [node]}")))?;

    let iter: ListIterator = nodes_term
        .decode()
        .map_err(|_| NifError::Term(Box::new("UiCanvas: nodes must be a list")))?;

    let nodes: Vec<UiNode> = iter.map(decode_ui_node).collect::<NifResult<_>>()?;

    Ok(UiCanvas { nodes })
}

/// UiNode をデコードする。
/// Elixir 側の形式: `{:node, rect, component, [children]}`
fn decode_ui_node(term: Term) -> NifResult<UiNode> {
    let (_, rect_t, component_t, children_t): (Atom, Term, Term, Term) =
        term.decode().map_err(|_| {
            NifError::Term(Box::new(
                "UiNode: expected {:node, rect, component, [children]}",
            ))
        })?;

    let rect = decode_ui_rect(rect_t)?;
    let component = decode_ui_component(component_t)?;

    let children_iter: ListIterator = children_t
        .decode()
        .map_err(|_| NifError::Term(Box::new("UiNode: children must be a list")))?;
    let children: Vec<UiNode> = children_iter
        .map(decode_ui_node)
        .collect::<NifResult<_>>()?;

    Ok(UiNode {
        rect,
        component,
        children,
    })
}

/// UiRect をデコードする。
/// Elixir 側の形式: `{anchor_atom, {offset_x, offset_y}, size}`
fn decode_ui_rect(term: Term) -> NifResult<UiRect> {
    let (anchor_t, offset_t, size_t): (Term, Term, Term) = term.decode().map_err(|_| {
        NifError::Term(Box::new(
            "UiRect: expected {anchor_atom, {offset_x, offset_y}, size}",
        ))
    })?;

    let anchor = decode_ui_anchor(anchor_t)?;
    let (ox, oy): (f64, f64) = offset_t
        .decode()
        .map_err(|_| NifError::Term(Box::new("UiRect: offset expected {x, y}")))?;
    let size = decode_ui_size(size_t)?;

    Ok(UiRect {
        anchor,
        offset: [ox as f32, oy as f32],
        size,
    })
}

/// UiAnchor をデコードする。
fn decode_ui_anchor(term: Term) -> NifResult<UiAnchor> {
    let s = atom_str(term)?;
    match s.as_str() {
        "top_left" => Ok(UiAnchor::TopLeft),
        "top_center" => Ok(UiAnchor::TopCenter),
        "top_right" => Ok(UiAnchor::TopRight),
        "middle_left" => Ok(UiAnchor::MiddleLeft),
        "center" => Ok(UiAnchor::Center),
        "middle_right" => Ok(UiAnchor::MiddleRight),
        "bottom_left" => Ok(UiAnchor::BottomLeft),
        "bottom_center" => Ok(UiAnchor::BottomCenter),
        "bottom_right" => Ok(UiAnchor::BottomRight),
        other => Err(NifError::Term(Box::new(format!(
            "UiAnchor: unknown '{other}'"
        )))),
    }
}

/// UiSize をデコードする。
/// - `:wrap` → `WrapContent`
/// - `{:fixed, w, h}` → `Fixed(w, h)`
fn decode_ui_size(term: Term) -> NifResult<UiSize> {
    if let Ok(s) = atom_str(term) {
        if s == "wrap" {
            return Ok(UiSize::WrapContent);
        }
        return Err(NifError::Term(Box::new(format!(
            "UiSize: unknown atom '{s}'"
        ))));
    }

    let tag = tag_of(term)?;
    if tag == "fixed" {
        let (_, w, h): (Atom, f64, f64) = term
            .decode()
            .map_err(|_| NifError::Term(Box::new("UiSize: expected {:fixed, w, h}")))?;
        return Ok(UiSize::Fixed(w as f32, h as f32));
    }

    Err(NifError::Term(Box::new(format!(
        "UiSize: unknown tag '{tag}'"
    ))))
}

/// UiComponent をデコードする。
fn decode_ui_component(term: Term) -> NifResult<UiComponent> {
    // :separator はアトム
    if let Ok(s) = atom_str(term) {
        if s == "separator" {
            return Ok(UiComponent::Separator);
        }
        return Err(NifError::Term(Box::new(format!(
            "UiComponent: unknown atom '{s}'"
        ))));
    }

    let tag = tag_of(term)?;

    match tag.as_str() {
        // {:vertical_layout, spacing, {pad_left, pad_top, pad_right, pad_bottom}}
        "vertical_layout" => {
            let (_, spacing, pad): (Atom, f64, (f64, f64, f64, f64)) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "vertical_layout: expected {:vertical_layout, spacing, {pl,pt,pr,pb}}",
                    ))
                })?;
            Ok(UiComponent::VerticalLayout {
                spacing: spacing as f32,
                padding: [pad.0 as f32, pad.1 as f32, pad.2 as f32, pad.3 as f32],
            })
        }
        // {:horizontal_layout, spacing, {pad_left, pad_top, pad_right, pad_bottom}}
        "horizontal_layout" => {
            let (_, spacing, pad): (Atom, f64, (f64, f64, f64, f64)) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "horizontal_layout: expected {:horizontal_layout, spacing, {pl,pt,pr,pb}}",
                    ))
                })?;
            Ok(UiComponent::HorizontalLayout {
                spacing: spacing as f32,
                padding: [pad.0 as f32, pad.1 as f32, pad.2 as f32, pad.3 as f32],
            })
        }
        // {:rect, {r,g,b,a}, corner_radius, border}
        // border: :none | {{r,g,b,a}, width}
        "rect" => {
            let (_, color_t, corner_radius, border_t): (Atom, Term, f64, Term) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "rect: expected {:rect, {r,g,b,a}, corner_radius, border}",
                    ))
                })?;
            let color = decode_color(color_t)?;
            let border = decode_optional_border(border_t)?;
            Ok(UiComponent::Rect {
                color,
                corner_radius: corner_radius as f32,
                border,
            })
        }
        // {:text, text, {r,g,b,a}, size, bold}
        "text" => {
            let (_, text, color_t, size, bold): (Atom, String, Term, f64, bool) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "text: expected {:text, text, {r,g,b,a}, size, bold}",
                    ))
                })?;
            let color = decode_color(color_t)?;
            Ok(UiComponent::Text {
                text,
                color,
                size: size as f32,
                bold,
            })
        }
        // {:button, label, action, {r,g,b,a}, min_width, min_height}
        "button" => {
            let (_, label, action, color_t, min_width, min_height): (
                Atom,
                String,
                String,
                Term,
                f64,
                f64,
            ) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "button: expected {:button, label, action, {r,g,b,a}, min_width, min_height}",
                ))
            })?;
            let color = decode_color(color_t)?;
            Ok(UiComponent::Button {
                label,
                action,
                color,
                min_width: min_width as f32,
                min_height: min_height as f32,
            })
        }
        // {:progress_bar, value, max, width, height, fg_high, fg_mid, fg_low, bg, corner_radius}
        "progress_bar" => {
            let (_, value, max, width, height, rest_t): (Atom, f64, f64, f64, f64, Term) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "progress_bar: expected {:progress_bar, value, max, width, height, {fg_high, fg_mid, fg_low, bg, corner_radius}}",
                    ))
                })?;
            let (fg_high_t, fg_mid_t, fg_low_t, bg_t, corner_radius): (
                Term,
                Term,
                Term,
                Term,
                f64,
            ) = rest_t.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "progress_bar: rest expected {fg_high, fg_mid, fg_low, bg, corner_radius}",
                ))
            })?;
            Ok(UiComponent::ProgressBar {
                value: value as f32,
                max: max as f32,
                width: width as f32,
                height: height as f32,
                fg_color_high: decode_color(fg_high_t)?,
                fg_color_mid: decode_color(fg_mid_t)?,
                fg_color_low: decode_color(fg_low_t)?,
                bg_color: decode_color(bg_t)?,
                corner_radius: corner_radius as f32,
            })
        }
        // {:world_text, world_x, world_y, world_z, text, {r,g,b,a}, {lifetime, max_lifetime}}
        "world_text" => {
            let (_, world_x, world_y, world_z, text, color_t, (lifetime, max_lifetime)): (
                Atom,
                f64,
                f64,
                f64,
                String,
                Term,
                (f64, f64),
            ) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "world_text: expected {:world_text, wx, wy, wz, text, {r,g,b,a}, {lifetime, max_lifetime}}",
                ))
            })?;
            let color = decode_color(color_t)?;
            Ok(UiComponent::WorldText {
                world_x: world_x as f32,
                world_y: world_y as f32,
                world_z: world_z as f32,
                text,
                color,
                lifetime: lifetime as f32,
                max_lifetime: max_lifetime as f32,
            })
        }
        // {:screen_flash, {r,g,b,a}}
        "screen_flash" => {
            let (_, color_t): (Atom, Term) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "screen_flash: expected {:screen_flash, {r,g,b,a}}",
                ))
            })?;
            let color = decode_color(color_t)?;
            Ok(UiComponent::ScreenFlash { color })
        }
        // {:spacing, amount}
        "spacing" => {
            let (_, amount): (Atom, f64) = term
                .decode()
                .map_err(|_| NifError::Term(Box::new("spacing: expected {:spacing, amount}")))?;
            Ok(UiComponent::Spacing {
                amount: amount as f32,
            })
        }
        other => Err(NifError::Term(Box::new(format!(
            "UiComponent: unknown tag '{other}'"
        )))),
    }
}

/// `{r, g, b, a}` タプルを `[f32; 4]` にデコードする。
fn decode_color(term: Term) -> NifResult<[f32; 4]> {
    let (r, g, b, a): (f64, f64, f64, f64) = term
        .decode()
        .map_err(|_| NifError::Term(Box::new("color: expected {r, g, b, a}")))?;
    Ok([r as f32, g as f32, b as f32, a as f32])
}

/// ボーダーをデコードする。
/// - `:none` → `None`
/// - `{{r,g,b,a}, width}` → `Some(([f32;4], f32))`
fn decode_optional_border(term: Term) -> NifResult<Option<([f32; 4], f32)>> {
    if let Ok(s) = atom_str(term) {
        if s == "none" {
            return Ok(None);
        }
        return Err(NifError::Term(Box::new(format!(
            "border: unknown atom '{s}'"
        ))));
    }

    let (color_t, width): (Term, f64) = term
        .decode()
        .map_err(|_| NifError::Term(Box::new("border: expected {{r,g,b,a}, width}")))?;
    let color = decode_color(color_t)?;
    Ok(Some((color, width as f32)))
}

/// カーソルグラブ要求をデコードする。
/// - `:grab`      → `Some(true)`
/// - `:release`   → `Some(false)`
/// - `:no_change` → `None`
fn decode_cursor_grab(term: Term) -> NifResult<Option<bool>> {
    let s = atom_str(term).map_err(|_| {
        NifError::Term(Box::new(
            "cursor_grab: expected :grab | :release | :no_change",
        ))
    })?;
    match s.as_str() {
        "grab" => Ok(Some(true)),
        "release" => Ok(Some(false)),
        "no_change" => Ok(None),
        other => Err(NifError::Term(Box::new(format!(
            "cursor_grab: unknown atom '{other}'"
        )))),
    }
}
