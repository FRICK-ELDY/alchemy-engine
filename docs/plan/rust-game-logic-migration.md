# Rust 側に残るゲームロジック — 移行課題一覧

> 作成日: 2025-03-06  
> 最終更新: 2025-03-06  
> アーキテクチャ原則「Elixir = SSoT」「Rust = 演算層」に沿い、ゲームロジック（数式・バランス・固有概念）を contents に寄せる設計の一環として整理。

---

## 概要

現状、以下のゲームロジックが Rust 側に残存している。contents 側への移行または NIF 注入による SSoT 化が望ましい。既に Elixir に移行済みの項目は「移行済み」と記載する。

---

## 課題一覧（サマリ）

| 課題ID | 対象 | 優先度 | 状態 |
|:---|:---|:---:|:---:|
| R-R1 | renderer UV・スプライトパラメータ | 中 | 未対応 |
| R-W1 | weapon.rs 武器数式（effective_cooldown 等） | 中 | 一部移行済み |
| R-W2 | 弾丸・当たり判定の damage 注入 | 中 | 移行済み |
| R-E1 | score_popup lifetime 減衰 | 低 | 移行済み |
| R-P1 | PlayerDamaged / SpecialEntityDamaged の dt 乗算 | 低 | 移行済み |
| R-C1 | constants.rs 物理・画面定数 | 中 | 未対応 |
| R-F1 | FirePattern と武器発射パターン | 中 | 未対応 |
| R-I1 | items.rs 磁石・収集半径 | 低 | 未対応 |
| R-S1 | spawn.rs スポーン位置（800〜1200px） | 低 | 未対応 |
| R-U1 | util.rs WAVES・is_elite_spawn | 低 | デッドコード |
| R-B1 | boss.rs（レガシー） | 低 | 未使用 |
| R-M1 | entity_params デフォルト定数 | 低 | 未対応 |

---

## 1. Render 層

### R-R1: renderer UV・スプライトパラメータ（優先度: 中）

**対象:** `native/render/src/renderer/mod.rs`

**現状:**
- アトラスレイアウト・オフセット（`PLAYER_ATLAS_OFFSET_X`, `SLIME_ATLAS_OFFSET_X` 等）がハードコード
- 敵種別別のスプライトサイズ（`enemy_sprite_size`）: kind 1=slime(40px), 2=bat(24px), 3=golem(64px) 等
- UV 計算関数（`player_anim_uv`, `slime_anim_uv`, `enemy_anim_uv` 等）が VampireSurvivor 固有のアトラス構造を参照
- ボス UV（`slime_king_uv`, `bat_lord_uv`, `stone_golem_uv`）が固定
- `ATLAS_W`, `FRAME_W` が固定値

**層間インターフェース違反:**
> 「固有の概念を扱っていないか？」— 敵名（Slime, Bat, Golem, Ghost, Skeleton, Slime King 等）が render 層に露出している。

**対応方針:**
- improvement-plan の **I-M** と同一
- contents にスプライトパラメータ（UV・サイズ・kind_id マッピング）の SSoT を定義
- DrawCommand に kind_id を渡し、Elixir 側から UV・サイズを注入する NIF 拡張、または `render_kind` → パラメータの汎用 lookup テーブルを NIF で注入

**影響ファイル:**
- `native/render/src/renderer/mod.rs`

---

## 2. Physics 層 — 定数

### R-C1: constants.rs 物理・画面定数（優先度: 中）

**対象:** `native/physics/src/constants.rs`

**現状のハードコード値:**

| 定数 | 値 | 備考 |
|:---|:---|:---|
| `SCREEN_WIDTH` | 1280 | ウィンドウ幅 |
| `SCREEN_HEIGHT` | 720 | ウィンドウ高さ |
| `MAP_WIDTH` | 4096 | マップ幅（set_world_size で上書き可能） |
| `MAP_HEIGHT` | 4096 | マップ高さ |
| `PLAYER_SIZE` / `SPRITE_SIZE` | 64 | スプライト・プレイヤーサイズ |
| `PLAYER_SPEED` | 200 | 移動速度 |
| `PLAYER_RADIUS` | 32 | 衝突判定半径 |
| `ENEMY_RADIUS` | 20 | 敵のデフォルト半径 |
| `BULLET_RADIUS` | 6 | 弾丸半径 |
| `INVINCIBLE_DURATION` | 0.5 | 無敵時間（秒） |
| `WEAPON_COOLDOWN` | 1.0 | 武器クールダウン（デフォルト） |
| `BULLET_SPEED` | 400 | 弾丸速度 |
| `BULLET_LIFETIME` | 3.0 | 弾丸生存時間 |
| `CELL_SIZE` | 80 | 空間ハッシュセルサイズ |
| `WEAPON_SEARCH_RADIUS` | 640 (SCREEN_WIDTH/2) | 武器の最近接敵探索半径 |
| `WAVES` | 難易度カーブ | Elixir SpawnSystem で代替済み、bin 専用 |

**対応方針:**
- 画面解像度・マップサイズは既に NIF で注入可能なものは注入済み
- 物理定数（`PLAYER_SPEED`, `BULLET_SPEED`, `INVINCIBLE_DURATION` 等）は contents から NIF で注入する設計を検討
- 現状は `set_entity_params` で敵・武器パラメータを注入しているため、プレイヤー移動速度等も同様に注入可能にする

---

## 3. Physics 層 — 武器

### R-W1: weapon.rs 武器数式（優先度: 中）

**対象:** `native/physics/src/weapon.rs`

**現状:**
- `effective_cooldown`: `base * (1.0 - (level - 1) * 0.07).max(base * 0.5)` — レベルごとのクールダウン短縮率
- `bullet_count`: `WeaponParams::bullet_table` から level で参照（params 注入済み）
- `bullet_table` 自体は Elixir から `set_entity_params` で注入可能

**移行済み:**
- `weapon_upgrade_desc`: contents の `WeaponFormulas.weapon_upgrade_descs` へ移行
- `precomputed_damage`: Elixir の `WeaponFormulas.effective_damage` で事前計算して `set_weapon_slots` で注入（R-W2）

**対応方針:**
- `effective_cooldown` の数式を contents に移し、Elixir が `set_weapon_slots` で `cooldown` にすでに計算済み値を渡す形にする
- または `WeaponParams` に `effective_cooldown(level)` 相当のテーブルを注入

### R-W2: 弾丸・当たり判定の damage 注入（優先度: 中）— 移行済み

**対象:** `native/physics/src/weapon.rs`, `set_weapon_slots` NIF

**現状:**
- `WeaponSlot::precomputed_damage` に Elixir の `WeaponFormulas.effective_damage` で計算済み値を注入
- 弾丸発射時は `precomputed_damage` をそのまま使用

### R-F1: FirePattern と武器発射パターン（優先度: 中）

**対象:** `native/physics/src/entity_params.rs`, `native/physics/src/game_logic/systems/weapons.rs`

**現状:**
- `FirePattern` enum: `Aimed`, `FixedUp`, `Radial`, `Whip`, `Aura`, `Piercing`, `Chain` — VampireSurvivor 武器種別に紐づく
- 各パターンの発射ロジック（扇状スプレッド角度、Radial の 4/8 方向、Whip の扇形角度、Aura 半径、Chain 連鎖数等）が weapons.rs に実装
- `WeaponParams::whip_range(level)` = `range + (level - 1) * 20`
- `WeaponParams::aura_radius(level)` = `range + (level - 1) * 15`
- `WeaponParams::chain_count_for_level(level)` = `chain_count + level / 2`

**層間インターフェース違反:**
> 「固有知識を持ちすぎていないか？」— 武器の挙動（magic_wand, axe, cross, whip, garlic, fireball, lightning）が physics 層に露出している。

**対応方針:**
- FirePattern は「パターン種別 ID」に抽象化し、具体的な角度・半径・連鎖数は params テーブルで注入
- または「発射パターン」を Elixir が毎フレーム計算して NIF で渡す方式（パフォーマンスとのトレードオフ）

---

## 4. Physics 層 — エンティティパラメータ

### R-M1: entity_params デフォルト定数（優先度: 低）

**対象:** `native/physics/src/entity_params.rs`

**現状:**
- `DEFAULT_ENEMY_RADIUS`: 16
- `DEFAULT_WHIP_RANGE`: 200
- `DEFAULT_AURA_RADIUS`: 150
- `DEFAULT_CHAIN_COUNT`: 1
- `CHAIN_BOSS_RANGE`: 600 — Chain 武器がボスに連鎖する最大距離
- `DEFAULT_PARTICLE_COLOR`: [1.0, 0.5, 0.1, 1.0]

**対応方針:**
- params テーブルに存在しない場合のフォールバックとして使用
- 新コンテンツ追加時は必ず params を注入する前提であれば、デフォルトは最小限でよい

---

## 5. Physics 層 — アイテム・スポーン

### R-I1: items.rs 磁石・収集半径（優先度: 低）

**対象:** `native/physics/src/game_logic/systems/items.rs`

**現状:**
- 磁石付与時の収集半径: `9999.0`（事実上全画面）
- 通常時の収集半径: `60.0`
- 磁石引き寄せ速度: `300.0 * dt`
- 磁石効果時間: `10.0` 秒（`w.magnet_timer = 10.0`）
- `ItemKind`: `Gem`, `Potion`, `Magnet` — VampireSurvivor 固有

**対応方針:**
- 収集半径・磁石効果時間・引き寄せ速度を NIF で注入、または `set_world_params` 的な NIF で一括注入

### R-S1: spawn.rs スポーン位置（優先度: 低）

**対象:** `native/physics/src/game_logic/systems/spawn.rs`

**現状:**
- `get_spawn_positions_around_player`: プレイヤー周囲 **800〜1200px** の円周上にスポーン
- `spawn_position_around_player` (util.rs): `min_dist`, `max_dist` を引数で受け取る汎用関数

**対応方針:**
- 800, 1200 を NIF 引数で受け取るか、`set_world_params` で注入

### R-U1: util.rs WAVES・is_elite_spawn（優先度: 低）— デッドコード

**対象:** `native/physics/src/util.rs`

**現状:**
- `WAVES`: 難易度カーブ `[(0,4,2), (60,2.5,4), (180,1.5,8), (360,1.0,12), (600,0.7,18)]`
- `current_wave`, `is_elite_spawn` — `game_window` バイナリ専用、NIF 経由では Elixir SpawnSystem が使用
- `#[allow(dead_code)]` 付与済み

**対応方針:**
- 残置または将来的に physics から削除

---

## 6. Physics 層 — ボス（レガシー）

### R-B1: boss.rs（優先度: 低）— 未使用

**対象:** `native/physics/src/game_logic/systems/boss.rs`

**現状:**
- `update_boss` は `physics_step` から呼ばれていない
- `systems/mod.rs` に `pub(crate) mod boss` が宣言されていないため、**未使用コード**
- 現在は `special_entity_snapshot` + `collide_special_entity_snapshot` でボス衝突を処理
- `GameWorldInner` に `boss` フィールドは存在しない（special_entity 方式に移行済み）

**対応方針:**
- 削除するか、レガシーとして明示的にドキュメント化

---

## 7. NIF 層 — 初期値・ハードコード

### world_nif.rs の create_world 初期値

**対象:** `native/nif/src/nif/world_nif.rs`

**現状:**
- プレイヤー初期位置: `SCREEN_WIDTH/2 - PLAYER_SIZE/2`, `SCREEN_HEIGHT/2 - PLAYER_SIZE/2`
- `player_max_hp`: 100
- `map_width` / `map_height`: `MAP_WIDTH` / `MAP_HEIGHT`（set_world_size で上書き可能）
- `rng` シード: 12345
- `PARTICLE_RNG_SEED`: 67890 (constants)

**対応方針:**
- プレイヤー初期位置・player_max_hp は NIF 引数で受け取るか、初回 sync で注入

---

## 8. Render 層 — 補間・プレイヤー前提

### render_bridge.rs

**対象:** `native/nif/src/render_bridge.rs`

**現状:**
- プレイヤー補間のため `PlayerSprite` を commands の先頭に置く規約を前提
- `PLAYER_SIZE`, `SCREEN_WIDTH`, `SCREEN_HEIGHT` でカメラオフセット計算
- ウィンドウタイトル・アトラスパスは引数で受け取り済み（Phase R-4）

**層間インターフェース違反:**
> 「本質的に知りたい情報か？」— プレイヤー座標の補間は描画のスムージングに必要。ただし「PlayerSprite が先頭」というコンテンツ固有の規約が render 層に漏れている。

**対応方針:**
- 補間対象を「カメラ追従エンティティ ID」等に抽象化するか、現状の規約をドキュメント化して維持

---

## 9. 移行済み項目（参考）

| 項目 | 移行先 |
|:---|:---|
| weapon_upgrade_desc | Content.VampireSurvivor.WeaponFormulas.weapon_upgrade_descs |
| 弾丸 damage | set_weapon_slots の precomputed_damage |
| score_popup lifetime | add_score_popup の lifetime 引数（Elixir から注入） |
| PlayerDamaged damage | set_enemy_damage_this_frame / SpecialEntitySnapshot.damage_this_frame |
| 敵・武器・ボス params | set_entity_params NIF |
| マップサイズ | set_world_size NIF |
| ボス永続状態 | special_entity_snapshot（スナップショット注入） |

---

## 関連ドキュメント

- [improvement-plan.md](../task/improvement-plan.md) — I-M, I-RG
- [docs/architecture/elixir/contents/vampire_survivor.md](../architecture/elixir/contents/vampire_survivor.md)
- [implementation.mdc](../../.cursor/rules/implementation.mdc) — 層間インターフェース設計の原則
