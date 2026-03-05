//! Path: native/nif/src/nif/decode/ui_canvas.rs
//! Summary: UiCanvas / UiNode / UiComponent の Elixir タプル → Rust 変換

use render::{UiAnchor, UiCanvas, UiComponent, UiNode, UiRect, UiSize};
use rustler::types::list::ListIterator;
use rustler::{Atom, Error as NifError, NifResult, Term};

use super::{atom_str, decode_color, tag_of};

/// UiCanvas をデコードする。
/// Elixir 側の形式: `{:canvas, [node]}`
pub fn decode_ui_canvas(term: Term) -> NifResult<UiCanvas> {
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
