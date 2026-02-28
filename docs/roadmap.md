# AlchemyEngine — 現状の切り分けとロードマップ

> このドキュメントは `vision.md` のビジョンを基に、**現在の実装状態の診断**と**やるべきことの優先順位**を整理したものです。

---

## 1. 現状診断：Engine / World / Rule の混在マップ

`vision.md` が定義する 3 層（Engine / World / Rule）に対して、現在のコードがどこに属しているかを整理する。

### 1-1. 正しく分離できているもの ✅

| コード | 正しい位置 | 理由 |
|:---|:---|:---|
| `physics/spatial_hash.rs` | Engine | どんなゲームにも必要な空間分割 |
| `physics/separation.rs` | Engine | エンティティ分離は汎用物理 |
| `physics/obstacle_resolve.rs` | Engine | 障害物押し出しは汎用物理 |
| `physics/rng.rs` | Engine | 決定論的乱数は汎用基盤 |
| `world/enemy.rs`（SoA 構造体） | Engine | エンティティの存在・座標管理は汎用 |
| `world/bullet.rs`（SoA 構造体） | Engine | 発射物の存在・座標管理は汎用 |
| `world/particle.rs` | Engine | パーティクルは汎用エフェクト基盤 |
| `world/game_loop_control.rs` | Engine | ループ制御は汎用基盤 |
| `game_nif/render_bridge.rs` | Engine | レンダリング補間は汎用基盤 |
| `game_render/` 全体 | Engine | 描画パイプラインは汎用基盤 |
| `game_audio/` 全体 | Engine | オーディオ基盤は汎用 |
| `GameEngine.SceneManager` | Engine | シーンスタック管理は汎用 |
| `GameEngine.EventBus` | Engine | イベント配信は汎用基盤 |
| `GameEngine.RoomSupervisor` | Engine | ルーム管理は汎用基盤 |
| `GameContent.VampireSurvivor` | Rule | ゲーム固有ロジックとして正しく分離 |
| `GameContent.SpawnSystem` | Rule | ウェーブ定義はルール |
| `GameContent.BossSystem` | Rule | ボス出現スケジュールはルール |
| `GameContent.LevelSystem` | Rule | 武器選択肢生成はルール |
| `GameContent.Scenes.*` | Rule | シーン実装はルール |

---

### 1-2. Engine に混入している World/Rule ❌

#### Rust 側（`game_simulation`）

| コード | 現在の位置 | あるべき位置 | 問題の内容 |
|:---|:---|:---|:---|
| `entity_params.rs`（EnemyParams 5種） | Engine（`game_simulation`） | Rule | Slime/Bat/Golem 等の具体的パラメータはVampireSurvivor専用 |
| `entity_params.rs`（WeaponParams 7種） | Engine（`game_simulation`） | Rule | 武器パラメータはVampireSurvivor専用 |
| `entity_params.rs`（BossParams 3種） | Engine（`game_simulation`） | Rule | ボスパラメータはVampireSurvivor専用 |
| `enemy.rs`（EnemyKind enum） | Engine（`game_simulation`） | Rule/World | Slime/Bat/Golem という具体的な種別はエンジンが知る必要がない |
| `weapon.rs`（WeaponKind enum） | Engine（`game_simulation`） | Rule | 武器の種類はVampireSurvivor専用 |
| `weapon.rs`（WeaponSlot 構造体） | Engine（`game_simulation`） | Rule | 武器スロットの概念はVampireSurvivor専用 |
| `boss.rs`（BossKind enum） | Engine（`game_simulation`） | Rule | ボスの種類はVampireSurvivor専用 |
| `world/boss.rs`（BossState） | Engine（`game_simulation`） | Rule | ボス状態管理はVampireSurvivor専用 |
| `game_logic/systems/weapons.rs` | Engine（`game_simulation`） | Rule | 7武器の発射ロジックはVampireSurvivor専用 |
| `game_logic/systems/boss.rs` | Engine（`game_simulation`） | Rule | ボスAIはVampireSurvivor専用 |
| `game_logic/systems/leveling.rs` | Engine（`game_simulation`） | Rule | 武器選択肢生成ロジックはVampireSurvivor専用 |
| `util.rs`（EXP計算・ウェーブ設定） | Engine（`game_simulation`） | Rule | EXP曲線・ウェーブ設定はVampireSurvivor専用 |
| `constants.rs`（MAP_WIDTH/HEIGHT等） | Engine（`game_simulation`） | World | マップサイズはワールド定義 |
| `FrameEvent`（`exp`, `level_up`フィールド） | Engine（`game_simulation`） | Rule | EXP・レベルアップの概念はVampireSurvivor専用 |

#### Rust 側（`game_nif`）

| コード | 現在の位置 | あるべき位置 | 問題の内容 |
|:---|:---|:---|:---|
| `action_nif.rs`（`add_weapon`, `skip_level_up`, `spawn_boss`） | Engine（`game_nif`） | Rule | 武器追加・レベルアップ・ボス操作はVampireSurvivor専用NIF |
| `read_nif.rs`（`get_level_up_data`, `get_weapon_levels`, `get_boss_info`） | Engine（`game_nif`） | Rule | 武器・ボス情報の読み取りはVampireSurvivor専用 |

#### Elixir 側（`game_engine`）

| コード | 現在の位置 | あるべき位置 | 問題の内容 |
|:---|:---|:---|:---|
| `GameEngine.GameBehaviour`（`entity_registry`コールバック） | Engine | Rule | エンティティレジストリの概念はルール固有 |
| `GameEngine.GameEvents`（`context`内の`weapon_levels`等） | Engine | Rule | `weapon_levels`, `level_up_pending`, `weapon_choices` はVampireSurvivor専用 |
| `game_engine.ex`（`add_weapon`, `skip_level_up`, `spawn_boss`） | Engine公開API | Rule | 武器・ボス操作はVampireSurvivorに依存した公開APIになっている |

---

### 1-3. 境界が曖昧なもの ⚠️

| コード | 現状 | 判断の難しさ |
|:---|:---|:---|
| `game_logic/systems/spawn.rs` | Engine（`game_simulation`） | スポーン位置生成アルゴリズム自体は汎用だが、VampireSurvivor前提のパラメータが混在 |
| `game_logic/systems/projectiles.rs` | Engine（`game_simulation`） | 弾丸の移動・衝突は汎用だが、ドロップ（Gem生成）はVampireSurvivor専用 |
| `game_logic/systems/items.rs` | Engine（`game_simulation`） | アイテム収集の仕組み自体は汎用だが、Gem/Potion/Magnetの具体的な効果はVampireSurvivor専用 |
| `game_logic/systems/collision.rs` | Engine（`game_simulation`） | 衝突判定は汎用だが、Ghost（障害物無視）の特殊処理はVampireSurvivor専用 |
| `game_logic/chase_ai.rs` | Engine（`game_simulation`） | 追跡AIのアルゴリズムは汎用だが、VampireSurvivor専用の前提がある |
| `GameEngine.MapLoader` | Engine | マップ定義はWorldの責務だが、現状はEngine内に固定値がある |
| `GameEngine.GameBehaviour` | Engine | `WorldBehaviour` と `RuleBehaviour` に分割すべきだが、現状は混在 |

---

## 2. やるべきこと（優先順位付き）

### Phase 1 — Elixir 側の `context` クリーンアップ（最優先・影響範囲小）

**目的**: エンジンが「武器」「レベルアップ」を知らない状態にする。

| タスク | 対象ファイル | 作業内容 |
|:---|:---|:---|
| `context` からルール固有キーを除去 | `GameEngine.GameEvents` | `weapon_levels`, `level_up_pending`, `weapon_choices` をシーン `state` に移す |
| `GameBehaviour.context_defaults/0` の整理 | `GameEngine.GameBehaviour` | ルール固有のデフォルト値をシーン側に移す |
| `GameEngine` 公開APIの整理 | `game_engine.ex` | `add_weapon`, `skip_level_up`, `spawn_boss` をエンジンAPIから除去し、`game_content` 側で直接NIF呼び出しにする |

**完了の定義**: `GameEngine.GameEvents` の `context` マップに `weapon_*`, `level_*`, `boss_*` キーが存在しない状態。

---

### Phase 2 — `GameBehaviour` の分割（2つ目のコンテンツ着手時）

**目的**: World と Rule の概念をElixir側で明確に分離する。

| タスク | 対象ファイル | 作業内容 |
|:---|:---|:---|
| `WorldBehaviour` の定義 | `game_engine/world_behaviour.ex`（新規） | `map_obstacles/0`, `entity_kinds/0`, `assets_path/0` を定義 |
| `RuleBehaviour` の定義 | `game_engine/rule_behaviour.ex`（新規） | `initial_scenes/0`, `physics_scenes/0`, `context_defaults/0` を定義 |
| `GameBehaviour` を廃止 | `game_engine/game_behaviour.ex` | `WorldBehaviour` + `RuleBehaviour` に置き換え |
| `VampireSurvivor` の分割 | `game_content/vampire_survivor.ex` | World定義モジュールとRule定義モジュールに分割 |

**完了の定義**: `GameContent.VampireSurvivorWorld` と `GameContent.VampireSurvivorRule` が独立して存在し、同じWorldに別のRuleを適用できる構造になっている状態。

---

### Phase 3 — Rust コアからルール固有型を除去（最大の変更・2つ目のコンテンツ具体化後）

**目的**: `game_simulation` クレートをエンジン汎用の物理・ECSライブラリにする。

#### Phase 3-A: パラメータの外部注入化

| タスク | 対象ファイル | 作業内容 |
|:---|:---|:---|
| `entity_params.rs` をNIF経由で注入可能にする | `game_simulation/entity_params.rs` | ハードコードされたパラメータテーブルを `HashMap<u8, EnemyParams>` 等に変更し、`set_entity_params` NIFで外部から設定できるようにする |
| `EnemyKind`, `WeaponKind`, `BossKind` enum を除去 | `game_simulation/enemy.rs` 等 | 具体的な種別enumを削除し、`kind_id: u8` のみで管理する |
| `constants.rs` のWorld依存定数を外部化 | `game_simulation/constants.rs` | `MAP_WIDTH`, `MAP_HEIGHT` 等をWorldから注入できるようにする |

#### Phase 3-B: ゲームシステムの分離

| タスク | 対象ファイル | 作業内容 |
|:---|:---|:---|
| 武器システムをRule側に移動 | `game_simulation/game_logic/systems/weapons.rs` | 武器発射ロジックをElixir側のRuleから設定可能な汎用「アタックシステム」に置き換える |
| ボスシステムをRule側に移動 | `game_simulation/game_logic/systems/boss.rs` | ボスAIをElixir側から設定可能な汎用「特殊エンティティシステム」に置き換える |
| レベリングシステムをRule側に移動 | `game_simulation/game_logic/systems/leveling.rs` | EXP・レベルアップ計算をElixir側（`GameContent.LevelSystem`）に完全移管 |
| `FrameEvent` からRule固有フィールドを除去 | `game_simulation/world/frame_event.rs` | `exp`, `level_up` を除去し、汎用的な `EntityRemoved { id, kind_id }` 等に変更 |

#### Phase 3-C: NIF インターフェースの整理

| タスク | 対象ファイル | 作業内容 |
|:---|:---|:---|
| `action_nif.rs` からRule固有NIFを除去 | `game_nif/nif/action_nif.rs` | `add_weapon`, `skip_level_up`, `spawn_boss` を汎用NIF（`set_entity_attribute`, `spawn_entity`等）に置き換え |
| `read_nif.rs` からRule固有NIFを除去 | `game_nif/nif/read_nif.rs` | `get_level_up_data`, `get_weapon_levels`, `get_boss_info` を除去 |

**完了の定義**: `game_simulation` クレートに `vampire`, `weapon`, `boss`, `exp`, `level` という単語が存在しない状態。

---

## 3. 現状の技術的負債サマリー

```
【負債の大きさ】

Elixir側 context汚染          ██░░░░░░░░  小（Phase 1で解消可能）
Elixir側 GameBehaviour混在    ████░░░░░░  中（Phase 2で解消可能）
Rust側 パラメータハードコード  ████████░░  大（Phase 3-Aで解消）
Rust側 ゲームシステム混在      ██████████  最大（Phase 3-Bで解消）
NIF インターフェース汚染       ██████░░░░  中（Phase 3-Cで解消）
```

---

## 4. 2つ目のコンテンツを作るために必要な最低限の作業

2つ目のゲームコンテンツを追加しようとしたとき、現状では以下の問題が発生する。

1. **Rust側のパラメータが固定**: `entity_params.rs` の敵・武器・ボスパラメータがVampireSurvivor専用のため、別ゲームの敵を定義できない
2. **武器システムが固定**: 7種の武器発射ロジックがハードコードされており、別の攻撃パターンを追加できない
3. **ボスシステムが固定**: 3種のボスAIがハードコードされており、別のボスを定義できない
4. **NIF APIが固定**: `add_weapon`, `spawn_boss` 等のNIF関数がVampireSurvivor専用のため、別ゲームから呼び出せない

**最低限の作業（2つ目のコンテンツ着手前に必須）**:
- Phase 1 の完了（Elixir context クリーンアップ）
- Phase 3-A の完了（パラメータ外部注入化）

これにより、同じRustエンジン上で異なるパラメータセットを持つ2つ目のゲームが動作できる状態になる。

---

## 5. 変更しない（変更すべきでない）もの

以下はビジョンに照らして正しく設計されており、現時点で変更する必要がない。

| コード | 理由 |
|:---|:---|
| `GameEngine.SceneManager` | シーンスタック管理はエンジン汎用として正しく設計されている |
| `GameEngine.EventBus` | イベント配信は汎用基盤として正しい |
| `GameEngine.RoomSupervisor` | ルーム管理は汎用基盤として正しい |
| `game_render/` 全体 | 描画パイプラインはエンジン汎用として正しい |
| `game_audio/` 全体 | オーディオ基盤はエンジン汎用として正しい |
| `physics/` 全体 | 物理演算ユーティリティはエンジン汎用として正しい |
| SoA 構造（EnemyWorld等） | データ構造自体は汎用。パラメータ注入さえ解決すれば問題ない |
| `RwLock` による競合戦略 | ロック設計は正しく、変更不要 |
| `GameContent.VampireSurvivor` の各シーン | Rule側として正しく分離されている |

---

*このドキュメントは `vision.md` の思想に基づいて作成されており、実装の進行に合わせて更新すること。*
*各 Phase の完了後は、このドキュメントの該当セクションに完了日を記録すること。*
