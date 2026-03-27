//! `proto/frame_injection.proto` に対応する injection 適用（prost）

use crate::pb;
use crate::physics::weapon::WeaponSlot;
use crate::physics::world::{GameWorldInner, SpecialEntitySnapshot};
use prost::Message;
use std::borrow::Cow;
use std::cmp::min;

/// 不正な kind_id で巨大ベクタ確保を避けるための上限。
/// 実運用で必要になれば params 側の実 ID 範囲に合わせて見直す。
const ENEMY_DAMAGE_KIND_ID_MAX: usize = 4095;

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

pub fn decode_injection_payload(bytes: &[u8]) -> Cow<'_, [u8]> {
    match pb::FrameInjectionEnvelope::decode(bytes) {
        Ok(env) => Cow::Owned(env.payload),
        Err(_) => Cow::Borrowed(bytes),
    }
}

pub fn apply_injection_from_pb(
    w: &mut GameWorldInner,
    bytes: &[u8],
) -> Result<(), prost::DecodeError> {
    let inj = pb::FrameInjection::decode(bytes)?;
    if let Some(v) = inj.player_input {
        w.player.input_dx = v.x;
        w.player.input_dy = v.y;
    }
    if let Some(v) = inj.player_snapshot {
        w.player_hp_injected = v.x;
        w.player_invincible_timer_injected = v.y;
    }
    if let Some(v) = inj.elapsed_seconds {
        // GameWorldInner は f32（物理ステップと同じ）。
        // protobuf では double のまま受けるため、ここで f32 へ丸める（巨大値では精度低下しうる仕様）。
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
            let clamped_max_id = min(max_id, ENEMY_DAMAGE_KIND_ID_MAX);
            if max_id > ENEMY_DAMAGE_KIND_ID_MAX {
                log::warn!(
                    "protobuf_frame_injection: enemy_damage_this_frame kind_id {} exceeds cap {}, clamping",
                    max_id,
                    ENEMY_DAMAGE_KIND_ID_MAX
                );
            }
            w.enemy_damage_this_frame.clear();
            w.enemy_damage_this_frame.resize(clamped_max_id + 1, 0.0);
            for p in ed.pairs {
                let i = p.kind_id as usize;
                if i <= ENEMY_DAMAGE_KIND_ID_MAX {
                    w.enemy_damage_this_frame[i] = p.damage;
                }
            }
        }
    }
    if let Some(snap) = inj.special_entity_snapshot {
        match snap.state {
            Some(pb::special_entity_snapshot::State::None(_)) | None => {
                w.special_entity_snapshot = None;
            }
            Some(pb::special_entity_snapshot::State::Alive(a)) => {
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
