//! Path: native/game_nif/src/nif/render_frame_nif.rs
//! Summary: RenderFrameBuffer 作成・push_render_frame NIF
//!
//! Phase R-2: Elixir 側（game_content）が DrawCommand リストを組み立てて
//! push_render_frame NIF 経由でバッファに書き込む。

use crate::render_frame_buffer::RenderFrameBuffer;
use game_render::{BossHudInfo, CameraParams, DrawCommand, GamePhase, HudData, RenderFrame};
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

/// Elixir 側から DrawCommand リスト・カメラ・HUD を受け取り、
/// RenderFrameBuffer に書き込む。
///
/// ## DrawCommand タプル形式
/// - `{:player_sprite, x, y, frame}`
/// - `{:sprite, x, y, kind_id, frame}`
/// - `{:particle, x, y, r, g, b, alpha, size}`
/// - `{:item, x, y, kind}`
/// - `{:obstacle, x, y, radius, kind}`
///
/// ## CameraParams タプル形式
/// - `{:camera_2d, offset_x, offset_y}`
///
/// ## HudData タプル形式（ネストタプル）
/// `{ {hp, max_hp, score, elapsed_seconds, level, exp, exp_to_next},
///    {enemy_count, bullet_count, fps, level_up_pending},
///    {weapon_choices, weapon_upgrade_descs, weapon_levels},
///    {magnet_timer, item_count, boss_info, phase, screen_flash_alpha, score_popups, kill_count} }`
///
/// - `boss_info`: `:none` または `{name, hp, max_hp}`
/// - `phase`: `:title` | `:playing` | `:game_over`
/// - `score_popups`: `[{x, y, value, lifetime}]`
/// - `weapon_levels`: `[{name, level}]`
/// - `weapon_upgrade_descs`: `[[desc_string]]`
#[rustler::nif]
pub fn push_render_frame(
    buf: ResourceArc<RenderFrameBuffer>,
    commands: Term,
    camera: Term,
    hud: Term,
) -> NifResult<Atom> {
    let commands = decode_commands(commands)?;
    let camera = decode_camera(camera)?;
    let hud = decode_hud(hud)?;

    buf.push(RenderFrame {
        commands,
        camera,
        hud,
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
///
/// `rustler::types::tuple::get_tuple` でタプルを `Vec<Term>` に変換し、
/// 先頭要素をアトム文字列として返す。要素数に依存しないため、
/// 任意のサイズのタプルに対して安全に使用できる。
fn tag_of(term: Term) -> NifResult<String> {
    let elems =
        get_tuple(term).map_err(|_| NifError::Term(Box::new("DrawCommand: expected tuple")))?;
    let first = elems
        .first()
        .ok_or_else(|| NifError::Term(Box::new("DrawCommand: empty tuple")))?;
    atom_str(*first)
}

fn decode_command(term: Term) -> NifResult<DrawCommand> {
    // タグアトムを先にデコードして match で分岐する。
    // これにより各バリアントのシグネチャが重複しても誤マッチが起きない。
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
        // Rustler は最大7要素タプルをサポートするため alpha と size を内部タプルにまとめる。
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
        // Rustler のタプルデコードは最大 7 要素まで対応しているため、
        // 8 要素になる末尾 5 要素（half_d, r, g, b, a）を内部タプルにまとめている。
        "box_3d" => {
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
                color: [color.0 as f32, color.1 as f32, color.2 as f32, color.3 as f32],
            })
        }
        // {:skybox, {top_r, top_g, top_b, top_a}, {bot_r, bot_g, bot_b, bot_a}}
        "skybox" => {
            let (_, top, bot): (Atom, (f64, f64, f64, f64), (f64, f64, f64, f64)) =
                term.decode().map_err(|_| {
                    NifError::Term(Box::new(
                        "skybox: expected {:skybox, {r,g,b,a}, {r,g,b,a}}",
                    ))
                })?;
            Ok(DrawCommand::Skybox {
                top_color: [top.0 as f32, top.1 as f32, top.2 as f32, top.3 as f32],
                bottom_color: [bot.0 as f32, bot.1 as f32, bot.2 as f32, bot.3 as f32],
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
        // Rustler のタプルデコードは最大 7 要素まで対応しているため、
        // 末尾 3 要素（fov_deg, near, far）を内部タプルにまとめている。
        "camera_3d" => {
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

/// HudData をネストタプルからデコードする。
///
/// Elixir 側の形式:
/// ```elixir
/// {
///   {hp, max_hp, score, elapsed_seconds, level, exp, exp_to_next},
///   {enemy_count, bullet_count, fps, level_up_pending},
///   {weapon_choices, weapon_upgrade_descs, weapon_levels},
///   {magnet_timer, item_count, boss_info, phase, screen_flash_alpha, score_popups, kill_count}
/// }
/// ```
fn decode_hud(term: Term) -> NifResult<HudData> {
    let (basic, counts, weapons, misc): (Term, Term, Term, Term) = term
        .decode()
        .map_err(|_| NifError::Term(Box::new("HudData: expected 4-element nested tuple")))?;

    let (hp, max_hp, score, elapsed_seconds, level, exp, exp_to_next): (
        f64,
        f64,
        u32,
        f64,
        u32,
        u32,
        u32,
    ) = basic.decode().map_err(|_| {
        NifError::Term(Box::new(
            "HudData.basic: expected {hp, max_hp, score, elapsed_seconds, level, exp, exp_to_next}",
        ))
    })?;

    let (enemy_count, bullet_count, fps, level_up_pending): (u32, u32, f64, bool) =
        counts.decode().map_err(|_| {
            NifError::Term(Box::new(
                "HudData.counts: expected {enemy_count, bullet_count, fps, level_up_pending}",
            ))
        })?;

    let (weapon_choices_term, weapon_upgrade_descs_term, weapon_levels_term): (Term, Term, Term) =
        weapons.decode().map_err(|_| {
            NifError::Term(Box::new(
                "HudData.weapons: expected {weapon_choices, weapon_upgrade_descs, weapon_levels}",
            ))
        })?;

    let (magnet_timer, item_count, boss_info_term, phase_term, screen_flash_alpha, score_popups_term, kill_count): (
        f64, u32, Term, Term, f64, Term, u32,
    ) = misc.decode().map_err(|_| {
        NifError::Term(Box::new(
            "HudData.misc: expected {magnet_timer, item_count, boss_info, phase, screen_flash_alpha, score_popups, kill_count}",
        ))
    })?;

    let weapon_choices = decode_string_list(weapon_choices_term)?;
    let weapon_upgrade_descs = decode_string_list_list(weapon_upgrade_descs_term)?;
    let weapon_levels = decode_weapon_levels(weapon_levels_term)?;
    let boss_info = decode_boss_info(boss_info_term)?;
    let phase = decode_game_phase(phase_term)?;
    let score_popups = decode_score_popups(score_popups_term)?;

    Ok(HudData {
        hp: hp as f32,
        max_hp: max_hp as f32,
        score,
        elapsed_seconds: elapsed_seconds as f32,
        level,
        exp,
        exp_to_next,
        enemy_count: enemy_count as usize,
        bullet_count: bullet_count as usize,
        fps: fps as f32,
        level_up_pending,
        weapon_choices,
        weapon_upgrade_descs,
        weapon_levels,
        magnet_timer: magnet_timer as f32,
        item_count: item_count as usize,
        boss_info,
        phase,
        screen_flash_alpha: screen_flash_alpha as f32,
        score_popups,
        kill_count,
    })
}

fn decode_string_list(term: Term) -> NifResult<Vec<String>> {
    let iter: ListIterator = term.decode()?;
    iter.map(|t| {
        t.decode::<String>()
            .map_err(|_| NifError::Term(Box::new("expected String in list")))
    })
    .collect()
}

fn decode_string_list_list(term: Term) -> NifResult<Vec<Vec<String>>> {
    let iter: ListIterator = term.decode()?;
    iter.map(decode_string_list).collect()
}

fn decode_weapon_levels(term: Term) -> NifResult<Vec<(String, u32)>> {
    let iter: ListIterator = term.decode()?;
    iter.map(|t| {
        let (name, level): (String, u32) = t
            .decode()
            .map_err(|_| NifError::Term(Box::new("weapon_levels: expected {String, u32}")))?;
        Ok((name, level))
    })
    .collect()
}

fn decode_boss_info(term: Term) -> NifResult<Option<BossHudInfo>> {
    // :none または {name, hp, max_hp}
    if let Ok(atom) = term.decode::<Atom>() {
        let s = atom_str(atom.to_term(term.get_env())).unwrap_or_default();
        if s == "none" {
            return Ok(None);
        }
    }

    let (name, hp, max_hp): (String, f64, f64) = term
        .decode()
        .map_err(|_| NifError::Term(Box::new("boss_info: expected :none or {name, hp, max_hp}")))?;

    Ok(Some(BossHudInfo {
        name,
        hp: hp as f32,
        max_hp: max_hp as f32,
    }))
}

fn decode_game_phase(term: Term) -> NifResult<GamePhase> {
    let atom: Atom = term
        .decode()
        .map_err(|_| NifError::Term(Box::new("GamePhase: expected atom")))?;
    let s = atom_str(atom.to_term(term.get_env()))?;

    match s.as_str() {
        "title" => Ok(GamePhase::Title),
        "playing" => Ok(GamePhase::Playing),
        "game_over" => Ok(GamePhase::GameOver),
        other => Err(NifError::Term(Box::new(format!(
            "GamePhase: unknown '{other}'"
        )))),
    }
}

fn decode_score_popups(term: Term) -> NifResult<Vec<(f32, f32, u32, f32)>> {
    let iter: ListIterator = term.decode()?;
    iter.map(|t| {
        let (x, y, value, lifetime): (f64, f64, u32, f64) = t.decode().map_err(|_| {
            NifError::Term(Box::new("score_popups: expected {x, y, value, lifetime}"))
        })?;
        Ok((x as f32, y as f32, value, lifetime as f32))
    })
    .collect()
}
