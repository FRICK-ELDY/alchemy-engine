# Rust 側に残るゲームロジック — 移行課題一覧

> 作成日: 2025-03-06  
> 最終更新: 2025-03-06  
> アーキテクチャ原則「Elixir = SSoT」「Rust = 演算層」に沿い、ゲームロジック（数式・バランス・固有概念）を contents に寄せる設計の一環として整理。

---

## 概要

現状、以下のゲームロジックが Rust 側に残存している。contents 側への移行または NIF 注入による SSoT 化が望ましい。

---

## 課題一覧（サマリ）

| 課題ID | 対象 | 優先度 | 状態 |
|:---|:---|:---:|:---:|
| R-R1 | renderer UV・スプライトパラメータ | 中 | 未対応 |
| R-C1 | constants.rs 物理・画面定数 | 中 | 未対応 |
| R-F1 | FirePattern と武器発射パターン | 中 | 未対応 |
| R-I1 | items.rs 磁石・収集半径 | 低 | 未対応 |
| R-S1 | spawn.rs スポーン位置（800〜1200px） | 低 | 未対応 |
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

---

## 関連ドキュメント

- [improvement-plan.md](../task/improvement-plan.md) — I-M, I-RG
- [docs/architecture/elixir/contents/vampire_survivor.md](../architecture/elixir/contents/vampire_survivor.md)
- [implementation.mdc](../../.cursor/rules/implementation.mdc) — 層間インターフェース設計の原則
