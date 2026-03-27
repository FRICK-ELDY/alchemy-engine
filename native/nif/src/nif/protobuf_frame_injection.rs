//! `proto/frame_injection.proto` に対応する injection 適用（prost）

use crate::physics::weapon::WeaponSlot;
use crate::physics::world::{GameWorldInner, SpecialEntitySnapshot};
use prost::Message;

/// `uint32` → `WeaponSlot.kind_id` 用 `u8`。255 超は `u8::MAX` に飽和し警告ログを出す。
fn u32_to_u8_clamped(field: &'static str, v: u32) -> u8 {
    if v > u8::MAX as u32 {
        log::warn!(
            "protobuf_frame_injection: {} value {} exceeds u8::MAX, clamping",
            field,
            v
        );
        u8::MAX
    } else {
        v as u8
    }
}

/// レガシー: ETF を bytes で包んでいた Zenoh/NIF 用エンベロープ
#[derive(Clone, PartialEq, Message)]
pub struct FrameInjectionEnvelopePb {
    #[prost(bytes = "vec", tag = "1")]
    pub payload: Vec<u8>,
}

pub fn decode_injection_payload(bytes: &[u8]) -> Vec<u8> {
    match FrameInjectionEnvelopePb::decode(bytes) {
        Ok(env) if !env.payload.is_empty() => env.payload,
        _ => bytes.to_vec(),
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct FrameInjectionPb {
    #[prost(message, optional, tag = "1")]
    pub player_input: Option<Vec2fPb>,
    #[prost(message, optional, tag = "2")]
    pub player_snapshot: Option<Vec2fPb>,
    #[prost(double, optional, tag = "3")]
    pub elapsed_seconds: Option<f64>,
    #[prost(message, optional, tag = "4")]
    pub weapon_slots: Option<WeaponSlotsListPb>,
    #[prost(message, optional, tag = "5")]
    pub enemy_damage_this_frame: Option<EnemyDamageListPb>,
    #[prost(message, optional, tag = "6")]
    pub special_entity_snapshot: Option<SpecialEntitySnapshotPb>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Vec2fPb {
    #[prost(float, tag = "1")]
    pub x: f32,
    #[prost(float, tag = "2")]
    pub y: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct WeaponSlotsListPb {
    #[prost(message, repeated, tag = "1")]
    pub slots: Vec<WeaponSlotPb>,
}

#[derive(Clone, PartialEq, Message)]
pub struct WeaponSlotPb {
    #[prost(uint32, tag = "1")]
    pub kind_id: u32,
    #[prost(uint32, tag = "2")]
    pub level: u32,
    #[prost(float, tag = "3")]
    pub cooldown: f32,
    #[prost(float, tag = "4")]
    pub cooldown_sec: f32,
    #[prost(int32, tag = "5")]
    pub precomputed_damage: i32,
}

#[derive(Clone, PartialEq, Message)]
pub struct EnemyDamageListPb {
    #[prost(message, repeated, tag = "1")]
    pub pairs: Vec<EnemyDamagePairPb>,
}

#[derive(Clone, PartialEq, Message)]
pub struct EnemyDamagePairPb {
    #[prost(uint32, tag = "1")]
    pub kind_id: u32,
    #[prost(float, tag = "2")]
    pub damage: f32,
}

#[derive(Clone, PartialEq, Message)]
pub struct SpecialEntitySnapshotPb {
    #[prost(oneof = "special_entity_pb::State", tags = "1,2")]
    pub state: Option<special_entity_pb::State>,
}

pub mod special_entity_pb {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum State {
        #[prost(message, tag = "1")]
        None(super::SpecialNonePb),
        #[prost(message, tag = "2")]
        Alive(super::SpecialAlivePb),
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct SpecialNonePb {}

#[derive(Clone, PartialEq, Message)]
pub struct SpecialAlivePb {
    #[prost(float, tag = "1")]
    pub x: f32,
    #[prost(float, tag = "2")]
    pub y: f32,
    #[prost(float, tag = "3")]
    pub radius: f32,
    #[prost(float, tag = "4")]
    pub damage: f32,
    #[prost(bool, tag = "5")]
    pub invincible: bool,
}

pub fn apply_injection_from_pb(
    w: &mut GameWorldInner,
    bytes: &[u8],
) -> Result<(), prost::DecodeError> {
    let inj = FrameInjectionPb::decode(bytes)?;
    if let Some(v) = inj.player_input {
        w.player.input_dx = v.x;
        w.player.input_dy = v.y;
    }
    if let Some(v) = inj.player_snapshot {
        w.player_hp_injected = v.x;
        w.player_invincible_timer_injected = v.y;
    }
    if let Some(v) = inj.elapsed_seconds {
        // GameWorldInner は f32（物理ステップと同じ）。protobuf では double のまま受け、ここで丸める。
        w.elapsed_seconds = v as f32;
    }
    if let Some(list) = inj.weapon_slots {
        w.weapon_slots_input = list
            .slots
            .into_iter()
            .map(|s| WeaponSlot {
                kind_id: u32_to_u8_clamped("weapon_slot.kind_id", s.kind_id),
                level: s.level,
                cooldown_timer: s.cooldown,
                cooldown_sec: s.cooldown_sec,
                precomputed_damage: s.precomputed_damage,
            })
            .collect();
    }
    if let Some(ed) = inj.enemy_damage_this_frame {
        if ed.pairs.is_empty() {
            w.enemy_damage_this_frame.clear();
        } else {
            let max_id = ed
                .pairs
                .iter()
                .map(|p| p.kind_id as usize)
                .max()
                .unwrap_or(0);
            w.enemy_damage_this_frame.clear();
            w.enemy_damage_this_frame.resize(max_id + 1, 0.0);
            for p in ed.pairs {
                w.enemy_damage_this_frame[p.kind_id as usize] = p.damage;
            }
        }
    }
    if let Some(snap) = inj.special_entity_snapshot {
        match snap.state {
            Some(special_entity_pb::State::None(_)) | None => {
                w.special_entity_snapshot = None;
            }
            Some(special_entity_pb::State::Alive(a)) => {
                w.special_entity_snapshot = Some(SpecialEntitySnapshot {
                    x: a.x,
                    y: a.y,
                    radius: a.radius,
                    damage_this_frame: a.damage,
                    invincible: a.invincible,
                });
            }
        }
    }
    Ok(())
}
