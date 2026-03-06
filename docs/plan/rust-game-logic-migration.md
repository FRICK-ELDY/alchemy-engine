# Rust 側に残るゲームロジック計算 — 移行課題一覧

> 作成日: 2026-03-06  
> アーキテクチャ原則「Elixir = SSoT」「Rust = 演算層」に沿い、ゲームロジック（数式・バランス）を contents に寄せる設計の一環として整理。

---

## 概要

現状、以下のゲームロジック計算が Rust 側に残存している。contents 側への移行または NIF 注入による SSoT 化が望ましい。

| 課題ID | 対象 | 優先度 | 備考 |
|:---|:---|:---:|:---|
| R-W1 | weapon.rs 武器数式 | 中 | 2026-03 で UI 表示は contents へ移行済み |
| R-W2 | 弾丸・当たり判定の damage 計算 | 中 | physics 毎フレームで実行 |
| R-E1 | effects.rs score_popup lifetime 減衰 | 低 | システム挙動寄り |
| R-P1 | PlayerDamaged / SpecialEntityDamaged の dt 乗算 | 低 | パラメータは Elixir 注入済み |
| R-R1 | renderer UV・スプライトパラメータ | 中 | I-M と同一 |

---

## R-W1: weapon.rs 武器数式（優先度: 中）

### 現状

`native/physics/src/weapon.rs` に以下の数式がハードコードされている。

| 関数 | 数式 | 用途 |
|:---|:---|:---|
| `effective_damage` | `base + (level-1) * max(base/4, 1)` | 弾丸 damage、敵撃破判定 |
| `effective_cooldown` | `base * (1 - (level-1)*0.07)`, min `base*0.5` | 攻撃間隔 |
| `whip_range` | `range + (level-1) * 20` | Whip 判定半径 |
| `aura_radius` | `range + (level-1) * 15` | Garlic オーラ半径 |
| `chain_count_for_level` | `chain_count + level/2` | 連鎖数 |
| `bullet_count` | `bullet_table[level]` | 発射弾数 |

### 進捗

- **2026-03**: `Content.VampireSurvivor.WeaponFormulas` を contents に追加。レベルアップカード表示（`weapon_upgrade_desc`）は Elixir 側で完結。`get_weapon_upgrade_descs` NIF は RenderComponent で未使用に。

### 残作業

1. **physics の damage 計算を Elixir 注入に移行**（オプション）  
   - 毎フレーム `set_weapon_slots` で渡すスロットに `effective_damage` を事前計算して含める  
   - または `spawn_projectile` 等の NIF で damage を Elixir から渡す設計に変更  
2. `weapon.rs` の `weapon_upgrade_desc` を削除し、NIF `get_weapon_upgrade_descs` を非推奨化（将来的に削除）

### 影響ファイル

- `native/physics/src/weapon.rs`
- `native/physics/src/game_logic/systems/weapons.rs`
- `native/nif/src/nif/read_nif.rs`（get_weapon_upgrade_descs）

---

## R-W2: 弾丸・当たり判定の damage 計算（優先度: 中）

### 現状

以下の箇所で弾丸の damage 値を使用している。damage は `WeaponSlot::effective_damage(params)` で算出。

| ファイル | 内容 |
|:---|:---|
| `physics/game_logic/systems/weapons.rs` | 弾丸スポーン時に `effective_damage` で damage を設定 |
| `physics/game_logic/systems/special_entity_collision.rs` | 弾丸 vs ボス: `w.bullets.damage[bi]` |
| `physics/game_logic/systems/projectiles.rs` | 弾丸 vs 敵: `w.bullets.damage[bi]` |
| `physics/game_logic/systems/boss.rs` | 弾丸 vs ボス: `w.bullets.damage[bi]`、接触 damage: `eff.boss_damage * dt` |

### 移行案

- Elixir が `spawn_projectile` 呼び出し時に damage を渡す（既に `spawn_projectile` は damage 引数を持つ）
- 武器発射は現状 Rust の `update_weapon_attacks` が `weapon_slots_input` と `params` から弾を生成しているため、Elixir から damage を渡すには `set_weapon_slots` のスキーマ変更か、別 NIF の追加が必要
- 簡易案: `weapon_slots_input` の各スロットに `precomputed_damage` を持たせ、Rust はそれを使用。Elixir が `WeaponFormulas.effective_damage` で計算して注入

### 影響ファイル

- `native/physics/src/game_logic/systems/weapons.rs`
- `native/physics/src/world/bullet.rs`
- `native/nif/src/nif/action_nif.rs`（set_weapon_slots, spawn_projectile）

---

## R-E1: effects.rs score_popup lifetime 減衰（優先度: 低）

### 現状

`native/physics/src/game_logic/systems/effects.rs` の `update_score_popups` で、`lifetime -= dt` による減衰を行っている。

### 評価

- ゲームバランスというより「表示時間」のシステム挙動。  
- contents への移行優先度は低い。将来的に DrawCommand に lifetime を渡し、renderer 側で減衰する設計も検討可。

### 影響ファイル

- `native/physics/src/game_logic/systems/effects.rs`
- `native/physics/src/game_logic/physics_step.rs`

---

## R-P1: PlayerDamaged / SpecialEntityDamaged の dt 乗算（優先度: 低）

### 現状

以下で `damage_per_sec * dt` または `bullets.damage[bi]` によりダメージ量を計算している。

| ファイル | 内容 |
|:---|:---|
| `physics/game_logic/physics_step.rs` | 障害物接触: `params.damage_per_sec * dt` |
| `physics/game_logic/systems/special_entity_collision.rs` | ボス接触: `snap.damage_per_sec * dt`、弾丸: `w.bullets.damage[bi]` |
| `physics/game_logic/systems/boss.rs` | ボス接触: `eff.boss_damage * dt` |

### 評価

- `damage_per_sec` と `bullets.damage` の**値**は既に Elixir の `set_entity_params` / `set_special_entity_snapshot` / 弾丸 spawn で注入済み。
- **計算式**（`x * dt`）は物理フレームの経過時間に基づく演算であり、Rust 側に残すのが自然。
- 移行の必要性は低い。

---

## R-R1: renderer UV・スプライトパラメータ（優先度: 中）

### 現状

`native/render/src/renderer/mod.rs` にアトラスオフセット・敵種別サイズ・UV 計算がハードコードされている。

### 対応

improvement-plan の **I-M** と同一。contents に SSoT を定義し、NIF 経由で注入する。

### 影響ファイル

- `native/render/src/renderer/mod.rs`

---

## 実施優先度サマリ

1. **R-W1**: 武器数式 — UI 表示は移行済み。physics 側の damage 注入は段階的検討
2. **R-R1 (I-M)**: 描画パラメータ — 既存 I-M タスクに含める
3. **R-W2**: 弾丸 damage — R-W1 の完了後に検討
4. **R-E1, R-P1**: 低優先度、現状維持で可
