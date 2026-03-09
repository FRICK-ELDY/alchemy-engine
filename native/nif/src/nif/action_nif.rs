//! Path: native/nif/src/nif/action_nif.rs
//! Summary: アクション NIF（set_weapon_slots, spawn_item, 汎用エンティティ操作 等）

use super::util::{lock_poisoned_err, params_not_loaded_err};
use crate::physics::constants::POPUP_Y_OFFSET;
use crate::physics::game_logic::systems::spawn::get_spawn_positions_around_player;
use crate::physics::item::ItemKind;
use crate::physics::weapon::WeaponSlot;
use crate::physics::world::{GameWorld, SpecialEntitySnapshot, DEFAULT_BULLET_HIT_COLOR};
use rustler::{Atom, NifResult, ResourceArc};

use crate::{alive, ok};

/// weapon_slots SSoT 移行: 武器スロットを Elixir 側から毎フレーム注入する NIF。
/// slots: [{kind_id, level, cooldown_timer, cooldown_sec, precomputed_damage}]
/// R-W1: cooldown_sec は Elixir の WeaponFormulas.effective_cooldown で事前計算。
/// R-W2: precomputed_damage は Elixir の WeaponFormulas.effective_damage で事前計算。
/// kind_id は u8 範囲（0..=255）であること。Elixir 側 entity_registry と一致させる。
#[rustler::nif]
pub fn set_weapon_slots(
    world: ResourceArc<GameWorld>,
    slots: Vec<(u8, u32, f64, f64, i32)>,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let new_slots: Vec<WeaponSlot> = slots
        .into_iter()
        .map(
            |(kind_id, level, cooldown, cooldown_sec, precomputed_damage)| WeaponSlot {
                kind_id,
                level,
                cooldown_timer: cooldown as f32,
                cooldown_sec: cooldown_sec as f32,
                precomputed_damage,
            },
        )
        .collect();
    w.weapon_slots_input = new_slots;
    Ok(ok())
}

/// Elixir SSoT 移行: 特殊エンティティの衝突用スナップショットを注入する NIF。
/// 毎フレーム on_nif_sync で呼ばれる。
/// snapshot: :none | {:alive, x, y, radius, damage_this_frame, invincible}
/// R-P2: damage_this_frame は contents が damage_per_sec * dt で事前計算して渡す。
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
                damage_this_frame: tuple.4 as f32,
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
        DEFAULT_BULLET_HIT_COLOR,
    );
    Ok(ok())
}

/// Phase 3-C: Elixir 側がスコアポップアップを描画用バッファに追加する NIF。
/// R-E1: lifetime を Elixir (contents) から注入。表示時間の SSoT を contents に移行。
/// EnemyKilled / BossDefeated イベント受信時に Elixir 側から呼び出す。
/// value: 表示するスコア値、lifetime: 表示時間（秒）
#[rustler::nif]
pub fn add_score_popup(
    world: ResourceArc<GameWorld>,
    x: f64,
    y: f64,
    value: u32,
    lifetime: f64,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.score_popups
        .push((x as f32, y as f32 + POPUP_Y_OFFSET, value, lifetime as f32));
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
    let positions = get_spawn_positions_around_player(&mut w, count);
    let used = w.enemies.spawn(&positions, kind_id, &ep);
    let base_hp = ep.max_hp * hp_multiplier as f32;
    for i in used {
        w.enemies.hp[i] = base_hp;
    }
    Ok(ok())
}
