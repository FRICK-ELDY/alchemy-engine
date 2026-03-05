//! Path: native/nif/src/nif/action_nif.rs
//! Summary: アクション NIF（set_weapon_slots, spawn_item, 汎用エンティティ操作 等）

use super::util::{lock_poisoned_err, params_not_loaded_err};
use physics::constants::{POPUP_LIFETIME, POPUP_Y_OFFSET};
use physics::game_logic::systems::spawn::get_spawn_positions_around_player;
use physics::item::ItemKind;
use physics::weapon::WeaponSlot;
use physics::world::{GameWorld, SpecialEntitySnapshot};
use rustler::{Atom, NifResult, ResourceArc};

use crate::{alive, ok};

/// I-2: 武器スロットを Elixir 側から毎フレーム注入する NIF。
/// Elixir 側 Rule state が武器の SSoT となり、毎フレームこの NIF で Rust に反映する。
/// slots: [{kind_id: u8, level: u32}] のリスト
#[rustler::nif]
pub fn set_weapon_slots(world: ResourceArc<GameWorld>, slots: Vec<(u8, u32)>) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let new_slots: Vec<WeaponSlot> = slots
        .into_iter()
        .map(|(kind_id, level)| {
            let existing_timer = w
                .weapon_slots
                .iter()
                .find(|s| s.kind_id == kind_id)
                .map(|s| s.cooldown_timer)
                .unwrap_or(0.0);
            WeaponSlot {
                kind_id,
                level,
                cooldown_timer: existing_timer,
            }
        })
        .collect();
    w.weapon_slots = new_slots;
    Ok(ok())
}

/// Elixir SSoT 移行: 特殊エンティティの衝突用スナップショットを注入する NIF。
/// 毎フレーム on_nif_sync で呼ばれる。
/// snapshot: :none | {:alive, x, y, radius, damage_per_sec, invincible}
#[rustler::nif]
pub fn set_special_entity_snapshot(
    world: ResourceArc<GameWorld>,
    snapshot: rustler::Term<'_>,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;

    if snapshot.is_atom() {
        w.special_entity_snapshot = None;
        return Ok(ok());
    }

    if let Ok(tuple) = snapshot.decode::<(Atom, f64, f64, f64, f64, bool)>() {
        if tuple.0 == alive() {
            w.special_entity_snapshot = Some(SpecialEntitySnapshot {
                x: tuple.1 as f32,
                y: tuple.2 as f32,
                radius: tuple.3 as f32,
                damage_per_sec: tuple.4 as f32,
                invincible: tuple.5,
            });
        } else {
            w.special_entity_snapshot = None;
        }
    } else {
        w.special_entity_snapshot = None;
    }

    Ok(ok())
}

/// Phase R-3: エンティティの HP を Elixir 側から設定する汎用 NIF。
///
/// entity_id の形式:
/// - `{:enemy, index}` — 敵エンティティのインデックス（タプル）
///
/// ボス用は廃止（Elixir SSoT 移行）。未対応の entity_id は無視する。
#[rustler::nif]
pub fn set_entity_hp(
    world: ResourceArc<GameWorld>,
    entity_id: rustler::Term<'_>,
    hp: f64,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Ok((tag, index)) = entity_id.decode::<(Atom, usize)>() {
        if tag == crate::enemy() && index < w.enemies.hp.len() && w.enemies.alive[index] != 0 {
            w.enemies.hp[index] = hp as f32;
        }
    }
    Ok(ok())
}

/// Phase R-3: 汎用弾丸スポーン NIF。
///
/// x/y は発射座標（Elixir 側が責任を持って渡す）、
/// vx/vy は速度ベクトル（正規化済み × speed）、
/// damage はダメージ値、lifetime は寿命（秒）、kind は BULLET_KIND_* 定数。
///
/// # 安全性
/// 座標の検証は行わない。呼び出し元（Elixir 側）が有効な座標を渡す責任を持つ。
/// ボス弾の場合は `update_boss_ai` の `{:alive, bx, by, ...}` パターンマッチにより
/// ボス存在が保証された状態でのみ呼ばれる。
/// `is_player` は常に `false`（プレイヤー弾は別経路で管理）。
#[rustler::nif]
#[allow(clippy::too_many_arguments)]
pub fn spawn_projectile(
    world: ResourceArc<GameWorld>,
    x: f64,
    y: f64,
    vx: f64,
    vy: f64,
    damage: i32,
    lifetime: f64,
    kind: u8,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.bullets.spawn_ex(
        x as f32,
        y as f32,
        vx as f32,
        vy as f32,
        damage,
        lifetime as f32,
        false, // is_player: プレイヤー弾は weapon システム経由で管理するため常に false
        kind,
    );
    Ok(ok())
}

/// Phase 3-C: Elixir 側がスコアポップアップを描画用バッファに追加する NIF。
/// EnemyKilled / BossDefeated イベント受信時に Elixir 側から呼び出す。
/// value: 表示するスコア値
#[rustler::nif]
pub fn add_score_popup(
    world: ResourceArc<GameWorld>,
    x: f64,
    y: f64,
    value: u32,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.score_popups
        .push((x as f32, y as f32 + POPUP_Y_OFFSET, value, POPUP_LIFETIME));
    Ok(ok())
}

/// Phase 3-B: Elixir 側のルールがアイテムドロップを制御するための NIF。
/// kind: 0=Gem, 1=Potion, 2=Magnet
#[rustler::nif]
pub fn spawn_item(
    world: ResourceArc<GameWorld>,
    x: f64,
    y: f64,
    kind: u8,
    value: u32,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let item_kind = match kind {
        0 => ItemKind::Gem,
        1 => ItemKind::Potion,
        2 => ItemKind::Magnet,
        _ => ItemKind::Gem,
    };
    w.items.spawn(x as f32, y as f32, item_kind, value);
    Ok(ok())
}

/// Phase R-3: HP 倍率付き敵スポーン NIF（旧 spawn_elite_enemy）。
/// プレイヤー周囲の座標生成を Rust 側で行い、スポーン直後に HP を倍率適用する。
/// 「エリート」という概念は Elixir 側（SpawnSystem）が持つ。
#[rustler::nif]
pub fn spawn_enemies_with_hp_multiplier(
    world: ResourceArc<GameWorld>,
    kind_id: u8,
    count: usize,
    hp_multiplier: f64,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let ep = w
        .params
        .get_enemy(kind_id)
        .ok_or_else(params_not_loaded_err)?
        .clone();
    let base_max_hp = ep.max_hp;
    let positions = get_spawn_positions_around_player(&mut w, count);
    let before_len = w.enemies.positions_x.len();
    w.enemies.spawn(&positions, kind_id, &ep);
    let after_len = w.enemies.positions_x.len();
    let base_hp = base_max_hp * hp_multiplier as f32;
    let mut applied = 0;
    for i in (0..after_len).rev() {
        if applied >= count {
            break;
        }
        if w.enemies.alive[i] != 0
            && w.enemies.kind_ids[i] == kind_id
            && (i >= before_len || (w.enemies.hp[i] - base_max_hp).abs() < 0.01)
        {
            w.enemies.hp[i] = base_hp;
            applied += 1;
        }
    }
    Ok(ok())
}
