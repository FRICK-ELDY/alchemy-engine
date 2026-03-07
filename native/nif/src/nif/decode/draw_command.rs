//! Path: native/nif/src/nif/decode/draw_command.rs
//! Summary: DrawCommand の Elixir タプル → Rust 変換
//!
//! ## 「定義の受け手」としての責務
//!
//! 本モジュールは **定義の受け手** である。Elixir 側（contents）が DrawCommand を組み立て、
//! 本 decode は受け取ったタプルを Rust の `DrawCommand` enum に変換するだけ。
//! タグ・フィールドの仕様は Elixir 側の SSoT（`docs/architecture/draw-command-spec.md`）に従う。
//! Rust は描画判断（メッシュ選択・UV 等）を持たず、定義に従って実行するのみ。

use render::DrawCommand;
use rustler::types::list::ListIterator;
use rustler::{Atom, Error as NifError, NifResult, Term};

use super::{decode_color, decode_mesh_vertices, tag_of, u32_to_u8};

/// P5-3: with_capacity で再アロケーションを抑制。典型的なフレームは 50〜500 コマンド。
pub fn decode_commands(term: Term) -> NifResult<Vec<DrawCommand>> {
    let iter: ListIterator = term.decode()?;
    let mut out = Vec::with_capacity(256);
    for item in iter {
        out.push(decode_command(item)?);
    }
    Ok(out)
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
                frame: u32_to_u8(frame, "player_sprite frame")?,
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
                kind: u32_to_u8(kind, "item kind")?,
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
                kind: u32_to_u8(kind, "obstacle kind")?,
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
        // {:grid_plane_verts, [{{x,y,z},{r,g,b,a}}, ...]}
        "grid_plane_verts" => {
            let (_, vertices_t): (Atom, Term) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "grid_plane_verts: expected {:grid_plane_verts, [vertices]}",
                ))
            })?;
            let vertices = decode_mesh_vertices(vertices_t, "grid_plane_verts")?;
            Ok(DrawCommand::GridPlaneVerts { vertices })
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

