//! Path: native/nif/src/nif/decode/msgpack_injection.rs
//! Summary: P5 set_frame_injection 用 MessagePack デコーダ
//!
//! Elixir の msgpax で pack された injection_map バイナリを rmp-serde でデコードし、
//! GameWorldInner に適用する。スキーマ: docs/architecture/messagepack-schema.md §7

use physics::weapon::WeaponSlot;
use physics::world::{GameWorldInner, SpecialEntitySnapshot};
use rmp_serde::from_slice;
use serde::Deserialize;

/// injection_map の MessagePack 構造。全フィールドオプショナル。
#[derive(Deserialize, Default)]
struct InjectionMsg {
    #[serde(default)]
    player_input: Option<[f64; 2]>,
    #[serde(default)]
    player_snapshot: Option<[f64; 2]>,
    #[serde(default)]
    elapsed_seconds: Option<f64>,
    #[serde(default)]
    weapon_slots: Option<Vec<WeaponSlotMsg>>,
    #[serde(default)]
    enemy_damage_this_frame: Option<Vec<(u64, f64)>>,
    #[serde(default)]
    special_entity_snapshot: Option<SpecialEntityMsg>,
}

/// weapon_slots: [[kind_id, level, cooldown, cooldown_sec, precomputed_damage], ...]
#[derive(Deserialize)]
struct WeaponSlotMsg(
    u8,  // kind_id
    u32, // level
    f64, // cooldown
    f64, // cooldown_sec
    i32, // precomputed_damage
);

/// special_entity_snapshot: nil | %{"t" => "alive", "x" => x, ...}
#[derive(Deserialize)]
struct SpecialEntityMsg {
    #[serde(rename = "t", default)]
    tag: Option<String>,
    #[serde(default)]
    x: Option<f64>,
    #[serde(default)]
    y: Option<f64>,
    #[serde(default)]
    radius: Option<f64>,
    #[serde(default)]
    damage: Option<f64>,
    #[serde(default)]
    invincible: Option<bool>,
}

impl SpecialEntityMsg {
    fn to_snapshot(&self) -> Option<SpecialEntitySnapshot> {
        if self.tag.as_deref() != Some("alive") {
            return None;
        }
        let x = self.x.unwrap_or(0.0) as f32;
        let y = self.y.unwrap_or(0.0) as f32;
        let radius = self.radius.unwrap_or(48.0) as f32;
        let damage = self.damage.unwrap_or(0.0) as f32;
        let invincible = self.invincible.unwrap_or(false);
        Some(SpecialEntitySnapshot {
            x,
            y,
            radius,
            damage_this_frame: damage,
            invincible,
        })
    }
}

/// MessagePack バイナリをデコードして GameWorldInner に適用する。
pub fn apply_injection_from_msgpack(
    w: &mut GameWorldInner,
    bytes: &[u8],
) -> Result<(), rmp_serde::decode::Error> {
    let msg: InjectionMsg = from_slice(bytes)?;

    if let Some([dx, dy]) = msg.player_input {
        w.player.input_dx = dx as f32;
        w.player.input_dy = dy as f32;
    }
    if let Some([hp, inv]) = msg.player_snapshot {
        w.player_hp_injected = hp as f32;
        w.player_invincible_timer_injected = inv as f32;
    }
    if let Some(elapsed) = msg.elapsed_seconds {
        w.elapsed_seconds = elapsed as f32;
    }
    if let Some(slots) = msg.weapon_slots {
        w.weapon_slots_input = slots
            .into_iter()
            .map(|s| WeaponSlot {
                kind_id: s.0,
                level: s.1,
                cooldown_timer: s.2 as f32,
                cooldown_sec: s.3 as f32,
                precomputed_damage: s.4,
            })
            .collect();
    }
    if let Some(list) = msg.enemy_damage_this_frame {
        if list.is_empty() {
            w.enemy_damage_this_frame.clear();
        } else {
            let max_id = list.iter().map(|(id, _)| *id as usize).max().unwrap_or(0);
            w.enemy_damage_this_frame.resize(max_id + 1, 0.0);
            w.enemy_damage_this_frame.fill(0.0);
            for (kind_id, damage) in list {
                let i = kind_id as usize;
                if i < w.enemy_damage_this_frame.len() {
                    w.enemy_damage_this_frame[i] = damage as f32;
                }
            }
        }
    }
    if let Some(ref snap) = msg.special_entity_snapshot {
        // Elixir は :none を %{"t" => "none"} でエンコードするため、常に map が来る。
        w.special_entity_snapshot = snap.to_snapshot();
    }

    Ok(())
}
