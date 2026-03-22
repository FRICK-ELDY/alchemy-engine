//! Path: native/nif/src/nif/decode/bert_injection.rs
//! Summary: set_frame_injection 用 Erlang term (ETF) デコーダ
//!
//! Elixir の :erlang.term_to_binary でエンコードされた injection_map バイナリを eetf でデコードし、
//! GameWorldInner に適用する。スキーマ: docs/architecture/messagepack-schema.md §7

use crate::physics::weapon::WeaponSlot;
use crate::physics::world::{GameWorldInner, SpecialEntitySnapshot};
use eetf::{Map, Term};
use num_traits::cast::ToPrimitive;
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

fn term_to_u8(t: &Term) -> Option<u8> {
    t.to_u8()
}

fn term_to_u32(t: &Term) -> Option<u32> {
    t.to_u32()
}

fn term_to_u64(t: &Term) -> Option<u64> {
    t.to_u64()
}

fn term_to_i32(t: &Term) -> Option<i32> {
    t.to_i32()
}

fn term_to_bool(t: &Term) -> Option<bool> {
    match t {
        Term::Atom(a) => match a.name.as_str() {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        },
        _ => t.to_u8().map(|u| u != 0),
    }
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

fn arr_f64(t: &Term) -> Vec<f64> {
    get_vec(t)
        .map(|v| v.iter().filter_map(|x| term_to_f64(x)).collect::<Vec<_>>())
        .unwrap_or_default()
}

fn parse_weapon_slot(t: &Term) -> Option<WeaponSlot> {
    let arr = get_vec(t)?;
    if arr.len() < 5 {
        log::warn!(
            "bert_injection: weapon_slot expects 5 elements [kind_id, level, cooldown, cooldown_sec, precomputed_damage], got {}",
            arr.len()
        );
        return None;
    }
    let kind_id = term_to_u8(*arr.get(0)?)?;
    let level = term_to_u32(*arr.get(1)?)?;
    let cooldown = term_to_f64(*arr.get(2)?)? as f32;
    let cooldown_sec = term_to_f64(*arr.get(3)?)? as f32;
    let precomputed_damage = term_to_i32(*arr.get(4)?)?;
    Some(WeaponSlot {
        kind_id,
        level,
        cooldown_timer: cooldown,
        cooldown_sec,
        precomputed_damage,
    })
}

fn parse_special_entity_snapshot(map: &Map) -> Option<SpecialEntitySnapshot> {
    if get_tag(map)? != "alive" {
        return None;
    }
    let x = map_get(map, "x").and_then(term_to_f64).unwrap_or(0.0) as f32;
    let y = map_get(map, "y").and_then(term_to_f64).unwrap_or(0.0) as f32;
    let radius = map_get(map, "radius").and_then(term_to_f64).unwrap_or(48.0) as f32;
    let damage = map_get(map, "damage").and_then(term_to_f64).unwrap_or(0.0) as f32;
    let invincible = map_get(map, "invincible").and_then(term_to_bool).unwrap_or(false);
    Some(SpecialEntitySnapshot {
        x,
        y,
        radius,
        damage_this_frame: damage,
        invincible,
    })
}

fn get_tag(map: &Map) -> Option<String> {
    map_get(map, "t").and_then(term_to_str)
}

/// Erlang term バイナリをデコードして GameWorldInner に適用する。
pub fn apply_injection_from_bert(
    w: &mut GameWorldInner,
    bytes: &[u8],
) -> Result<(), eetf::DecodeError> {
    let term = Term::decode(Cursor::new(bytes))?;
    let map = get_map(&term).ok_or_else(|| {
        eetf::DecodeError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "injection_map: expected map",
        ))
    })?;

    if let Some(player_input) = map_get(map, "player_input") {
        let arr = arr_f64(player_input);
        if arr.len() >= 2 {
            w.player.input_dx = arr[0] as f32;
            w.player.input_dy = arr[1] as f32;
        }
    }
    if let Some(player_snapshot) = map_get(map, "player_snapshot") {
        let arr = arr_f64(player_snapshot);
        if arr.len() >= 2 {
            w.player_hp_injected = arr[0] as f32;
            w.player_invincible_timer_injected = arr[1] as f32;
        }
    }
    if let Some(elapsed) = map_get(map, "elapsed_seconds").and_then(term_to_f64) {
        w.elapsed_seconds = elapsed as f32;
    }
    if let Some(weapon_slots) = map_get(map, "weapon_slots") {
        if let Some(list) = get_vec(weapon_slots) {
            w.weapon_slots_input = list.iter().filter_map(|t| parse_weapon_slot(t)).collect();
        }
    }
    if let Some(enemy_damage) = map_get(map, "enemy_damage_this_frame") {
        if let Some(list) = get_vec(enemy_damage) {
            if list.is_empty() {
                w.enemy_damage_this_frame.clear();
            } else {
                let mut max_id: usize = 0;
                let mut damage_map: Vec<(usize, f32)> = Vec::new();
                for item in list {
                    if let Some(arr) = get_vec(item) {
                        let kind_id = arr.get(0).and_then(|t| term_to_u64(*t).map(|u| u as usize));
                        let damage = arr.get(1).and_then(|t| term_to_f64(*t));
                        if let (Some(i), Some(d)) = (kind_id, damage) {
                            max_id = max_id.max(i);
                            damage_map.push((i, d as f32));
                        }
                    }
                }
                w.enemy_damage_this_frame.resize(max_id + 1, 0.0);
                w.enemy_damage_this_frame.fill(0.0);
                for (i, damage) in damage_map {
                    if i < w.enemy_damage_this_frame.len() {
                        w.enemy_damage_this_frame[i] = damage;
                    }
                }
            }
        }
    }
    if let Some(snap_term) = map_get(map, "special_entity_snapshot") {
        if let Some(snap_map) = get_map(snap_term) {
            w.special_entity_snapshot = parse_special_entity_snapshot(snap_map);
        }
    }

    Ok(())
}
