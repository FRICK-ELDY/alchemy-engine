# Rust 側に残るゲームロジック計算 — 移行課題一覧

> 作成日: 2025-03-06  
> アーキテクチャ原則「Elixir = SSoT」「Rust = 演算層」に沿い、ゲームロジック（数式・バランス）を contents に寄せる設計の一環として整理。

---

## 概要

現状、以下のゲームロジック計算が Rust 側に残存している。contents 側への移行または NIF 注入による SSoT 化が望ましい。

| 課題ID | 対象 | 優先度 | 備考 |
|:---|:---|:---:|:---|
| R-W1 | weapon.rs 武器数式 | 中 | 2025-03 で UI 表示は contents へ移行済み |
| R-W2 | 弾丸・当たり判定の damage 計算 | 中 | physics 毎フレームで実行 |
| R-E1 | effects.rs score_popup lifetime 減衰 | 低 | システム挙動寄り |
| R-P1 | PlayerDamaged / SpecialEntityDamaged の dt 乗算 | 低 | パラメータは Elixir 注入済み。R-P2 で contents 側計算を検討 |
| R-P2 | x * dt を contents 側で計算 | 低 | 将来課題。dt 概念を入れてから Rust 側計算を削除 |
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

- **2025-03**: `Content.VampireSurvivor.WeaponFormulas` を contents に追加。レベルアップカード表示（`weapon_upgrade_desc`）は Elixir 側で完結。`get_weapon_upgrade_descs` NIF は RenderComponent で未使用に。
- **2025-03**: R-W1 完了。`weapon.rs` の `weapon_upgrade_desc` を削除、NIF `get_weapon_upgrade_descs` を削除（contents の `WeaponFormulas.weapon_upgrade_descs` で Elixir 側完結）。

### 残作業

1. **physics の damage 計算を Elixir 注入に移行**（オプション、R-W2 で検討）  
   - 毎フレーム `set_weapon_slots` で渡すスロットに `effective_damage` を事前計算して含める  
   - または `spawn_projectile` 等の NIF で damage を Elixir から渡す設計に変更  
2. ~~`weapon.rs` の `weapon_upgrade_desc` を削除し、NIF `get_weapon_upgrade_descs` を非推奨化（将来的に削除）~~ → **2025-03 完了**

### 影響ファイル

- `native/physics/src/weapon.rs`（weapon_upgrade_desc 削除済み）
- `native/physics/src/game_logic/systems/weapons.rs`（damage 計算は現状 Rust 側）
- ~~`native/nif/src/nif/read_nif.rs`（get_weapon_upgrade_descs）~~ 削除済み

---

## R-W2: 弾丸・当たり判定の damage 計算（優先度: 中）

### 現状

以下の箇所で弾丸の damage 値を使用している。**2025-03 完了**: damage は `WeaponSlot::precomputed_damage` で Elixir 注入済み。

| ファイル | 内容 |
|:---|:---|
| `physics/game_logic/systems/weapons.rs` | 弾丸スポーン時に `precomputed_damage` を使用（R-W2 移行済み） |
| `physics/game_logic/systems/special_entity_collision.rs` | 弾丸 vs ボス: `w.bullets.damage[bi]` |
| `physics/game_logic/systems/projectiles.rs` | 弾丸 vs 敵: `w.bullets.damage[bi]` |
| `physics/game_logic/systems/boss.rs` | 弾丸 vs ボス: `w.bullets.damage[bi]`、接触 damage: `eff.boss_damage * dt` |

### 進捗

- **2025-03**: R-W2 完了。`set_weapon_slots` のスキーマに `precomputed_damage` を追加。Elixir の `WeaponFormulas.effective_damage` で事前計算して注入。Rust の `WeaponSlot::effective_damage` を削除。
- **方針**: 新規 contents では `weapon_slots_for_nif/2` を実装すること。1 引数版のみだと precomputed_damage が 0 になり全武器ダメージ 0 となる。

### 影響ファイル

- `native/physics/src/game_logic/systems/weapons.rs` — precomputed_damage 使用
- `native/physics/src/weapon.rs` — effective_damage 削除、precomputed_damage 追加
- `native/nif/src/nif/action_nif.rs` — set_weapon_slots スキーマ変更

---

## R-E1: effects.rs score_popup lifetime 減衰（優先度: 低）

### 現状

`native/physics/src/game_logic/systems/effects.rs` の `update_score_popups` で、`lifetime -= dt` による減衰を行っている。

### 進捗

- **2025-03**: R-E1 完了。`add_score_popup` に lifetime 引数を追加。表示時間の初期値を contents の `SpawnComponent.score_popup_lifetime()` で SSoT 化。`lifetime -= dt` の減衰は物理フレームに基づく演算のため Rust 側に残す。

### 影響ファイル

- `native/physics/src/game_logic/systems/effects.rs` — 減衰ロジック（Rust 側維持）
- `native/nif/src/nif/action_nif.rs` — add_score_popup に lifetime 引数追加

---

## R-P1: PlayerDamaged / SpecialEntityDamaged の dt 乗算（優先度: 低）

### 現状

以下で `damage_per_sec * dt` または `bullets.damage[bi]` によりダメージ量を計算している。

| ファイル | 内容 |
|:---|:---|
| `physics/game_logic/physics_step.rs` | 障害物接触: `params.damage_per_sec * dt` |
| `physics/game_logic/systems/special_entity_collision.rs` | ボス接触: `snap.damage_per_sec * dt`、弾丸: `w.bullets.damage[bi]` |
| `physics/game_logic/systems/boss.rs` | ボス接触: `eff.boss_damage * dt` |

### 進捗

- **2025-03**: R-P1 完了（現状維持の設計判断）。`damage_per_sec` と `bullets.damage` の**値**は Elixir 注入済み。計算式 `x * dt` は物理フレームの経過時間に基づく演算であり、physics 層の責務として Rust 側に残す。

### 影響ファイル

- `physics/game_logic/physics_step.rs` — 障害物接触 dmg 計算（コメント追加）
- `physics/game_logic/systems/special_entity_collision.rs` — ボス接触・弾丸 dmg（コメント追加）
- `physics/game_logic/systems/boss.rs` — ボス接触 dmg（コメント追加）

### 将来課題

- **R-P2**: `x * dt` の物理フレーム計算を contents 側で行えるようにする。手順: (1) まず `dt` の概念を Elixir/contents に導入し、`Core.Formula` の標準入力や NIF 経由で `dt` を利用できるようにする。(2) その後、Rust 側の `x * dt` 計算を削除し、contents が事前計算した damage を注入する設計に移行する。

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

1. ~~**R-W1**~~ 完了
2. ~~**R-W2**~~ 完了（弾丸 damage は precomputed_damage で Elixir 注入）
3. **R-R1 (I-M)**: 描画パラメータ — 既存 I-M タスクに含める
4. ~~**R-E1**~~ 完了（表示時間の初期値は contents SSoT）
5. ~~**R-P1**~~ 完了（dt 乗算は physics 層の責務として現状維持）
6. **R-P2**: `x * dt` を contents 側で計算可能にする — 将来課題
