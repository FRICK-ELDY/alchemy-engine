# ゲームコンテンツ詳細（VampireSurvivor）

## 概要

`game_content` アプリケーションは `WorldBehaviour` と `RuleBehaviour` を実装したゲーム固有のコンテンツを提供します。現在は **Vampire Survivor クローン** が実装されています。

World と Rule は分離されており、`config.exs` で組み合わせを指定します。

```elixir
config :game_server, :current_world, GameContent.VampireSurvivorWorld
config :game_server, :current_rule,  GameContent.VampireSurvivorRule
```

---

## `vampire_survivor_world.ex` — WorldBehaviour 実装

「舞台」の定義。マップサイズ・エンティティ種別・アセットパス・Rust へのパラメータ注入を担当する。

```elixir
defmodule GameContent.VampireSurvivorWorld do
  @behaviour GameEngine.WorldBehaviour

  @impl true
  def assets_path, do: "vampire_survivor"

  @impl true
  def entity_registry do
    %{
      enemies: %{slime: 0, bat: 1, golem: 2, skeleton: 3, ghost: 4},
      weapons: %{magic_wand: 0, axe: 1, cross: 2, whip: 3, fireball: 4, lightning: 5, garlic: 6},
      bosses:  %{slime_king: 0, bat_lord: 1, stone_golem: 2},
    }
  end

  @impl true
  def setup_world_params(world_ref) do
    GameEngine.NifBridge.set_world_size(world_ref, 4096.0, 4096.0)
    GameEngine.NifBridge.set_entity_params(world_ref, enemy_params(), weapon_params(), boss_params())
  end
end
```

### エンティティパラメータ（Elixir → Rust 注入）

**敵パラメータ（`enemy_params/0`）:**

| ID | 種別 | HP | 速度 | 半径 | ダメージ/秒 | 障害物すり抜け |
|:---|:---|:---|:---|:---|:---|:---|
| 0 | Slime | 30 | 80 | 20 | 20 | ✗ |
| 1 | Bat | 15 | 160 | 12 | 10 | ✗ |
| 2 | Golem | 150 | 40 | 32 | 40 | ✗ |
| 3 | Skeleton | 60 | 60 | 22 | 15 | ✗ |
| 4 | Ghost | 40 | 100 | 16 | 12 | ✅（壁すり抜け） |

**武器パラメータ（`weapon_params/0`）:**

| ID | 種別 | ダメージ | クールダウン | FirePattern |
|:---|:---|:---|:---|:---|
| 0 | magic_wand | 10 | 1.0s | Aimed（扇状） |
| 1 | axe | 25 | 1.5s | FixedUp（上方向） |
| 2 | cross | 15 | 2.0s | Radial（全方向） |
| 3 | whip | 30 | 1.0s | Whip（扇形判定） |
| 4 | fireball | 20 | 1.0s | Piercing（貫通） |
| 5 | lightning | 15 | 1.0s | Chain（連鎖） |
| 6 | garlic | 1 | 0.2s | Aura（オーラ） |

**ボスパラメータ（`boss_params/0`）:**

| ID | 種別 | HP | 速度 | 特殊行動インターバル |
|:---|:---|:---|:---|:---|
| 0 | Slime King | 1,000 | 60 | 5.0s |
| 1 | Bat Lord | 2,000 | 200 | 4.0s |
| 2 | Stone Golem | 5,000 | 30 | 6.0s |

---

## `vampire_survivor_rule.ex` — RuleBehaviour 実装

「遊び方」の定義。シーン構成・スポーン/ボス/レベルアップ制御・ボスAI・アイテムドロップを担当する。

### 主要コールバック

| コールバック | 説明 |
|:---|:---|
| `initial_scenes/0` | `[{Playing, %{}}]` |
| `initial_weapons/0` | `[:magic_wand]` |
| `generate_weapon_choices/1` | `LevelSystem.generate_weapon_choices/1` に委譲 |
| `on_entity_removed/4` | アイテムドロップ（Gem/Potion/Magnet）を `spawn_item` NIF で実行 |
| `on_boss_defeated/4` | Gem を10個散布 |
| `update_boss_ai/2` | SlimeKing/BatLord/StoneGolem の AI を Elixir 側で制御 |

### アイテムドロップ確率

| アイテム | 確率 | 効果 |
|:---|:---|:---|
| Magnet | 2% | 画面内全 Gem を自動吸引 |
| Potion | 5%（累積 7%） | HP +20 回復 |
| Gem | 残り 93% | EXP 取得（敵種別の報酬値） |

### ボスAI（`update_boss_ai/2`）

Elixir 側で毎フレーム呼び出され、`set_boss_velocity` / `set_boss_phase_timer` / `fire_boss_projectile` NIF を通じてボスを制御する。

| ボス | 通常移動 | 特殊行動（インターバルごと） |
|:---|:---|:---|
| SlimeKing | プレイヤー追跡（速度 60） | 周囲8方向にスライムをスポーン |
| BatLord | プレイヤー追跡（速度 200） | ダッシュ攻撃（速度 500、600ms 無敵） |
| StoneGolem | プレイヤー追跡（速度 30） | 4方向に岩弾を発射 |

---

## `entity_params.ex` — Elixir 側パラメータテーブル

Elixir 側が EXP・スコア・ボスパラメータの SSoT を持つモジュール。

```elixir
defmodule GameContent.EntityParams do
  # 敵 EXP 報酬
  @enemy_exp_rewards %{0 => 5, 1 => 3, 2 => 8, 3 => 20, 4 => 10}

  # ボス EXP 報酬
  @boss_exp_rewards %{0 => 200, 1 => 400, 2 => 800}

  # スコア = EXP × 2
  @score_per_exp 2

  # Phase 3-B: ボスAI 制御用パラメータ（速度・特殊行動インターバル等）
  @boss_params %{
    @boss_slime_king  => %{speed: 60.0, special_interval: 5.0},
    @boss_bat_lord    => %{speed: 200.0, special_interval: 4.0, dash_speed: 500.0, dash_duration_ms: 600},
    @boss_stone_golem => %{speed: 30.0, special_interval: 6.0, projectile_speed: 200.0, projectile_damage: 50, projectile_lifetime: 3.0},
  }
end
```

---

## シーン構成

```mermaid
graph TD
    SM[SceneManager スタック]
    PL[Playing\nベースシーン・常駐]
    LU[LevelUp\npush: レベルアップ時]
    BA[BossAlert\npush: ボス出現時]
    GO[GameOver\nreplace: 死亡時]

    SM --> PL
    PL -->|push| LU
    PL -->|push| BA
    PL -->|replace| GO
    LU -->|pop| PL
    BA -->|pop| PL
    GO -->|replace| PL
```

### `scenes/playing.ex` — プレイ中シーン

メインゲームプレイを管理するシーン。`update/2` で毎フレーム処理を行います。

**Playing シーン state（Elixir SSoT）:**

| キー | 説明 |
|:---|:---|
| `level` | 現在レベル |
| `exp` | 現在 EXP |
| `exp_to_next` | 次レベルまでの必要 EXP |
| `weapon_levels` | `%{weapon_atom => level}` |
| `level_up_pending` | レベルアップ待ちフラグ |
| `weapon_choices` | レベルアップ選択肢リスト |
| `boss_kind_id` | 現在のボス種別 ID（`nil` = ボスなし） |
| `boss_hp` | ボス HP（Elixir SSoT） |
| `boss_max_hp` | ボス最大 HP |
| `spawned_bosses` | 出現済みボス種別リスト |
| `elapsed_sec` | 経過時間（秒） |
| `score` | スコア |
| `kill_count` | 撃破数 |

**トランジション:**
```elixir
# レベルアップ
{:transition, {:push, Scenes.LevelUp, %{choices: choices}}, new_state}

# ボス出現
{:transition, {:push, Scenes.BossAlert, %{boss_kind: :slime_king}}, new_state}

# ゲームオーバー
{:transition, {:replace, Scenes.GameOver, %{score: score, elapsed: elapsed}}, new_state}
```

---

### `scenes/level_up.ex` — レベルアップ選択シーン

武器選択肢を表示し、プレイヤーの選択を待ちます。

- `auto_select: true` — 3 秒タイムアウトで自動選択（最初の選択肢）
- Esc / 1 / 2 / 3 キーで選択可能
- 選択後は `:pop` で Playing シーンに戻る

---

### `scenes/boss_alert.ex` — ボス出現アラートシーン

ボス出現を 3 秒間アナウンスし、その後ボスをスポーンして `:pop` します。

```elixir
@impl true
def update(context, %{boss_kind: boss_kind, alert_ms: alert_ms} = state) do
  if context.now - alert_ms >= BossSystem.alert_duration_ms() do
    kind_id = VampireSurvivorWorld.entity_registry().bosses[boss_kind]
    GameEngine.NifBridge.spawn_boss(context.world_ref, kind_id)
    {:transition, :pop, state}
  else
    {:continue, state}
  end
end
```

---

### `scenes/game_over.ex` — ゲームオーバーシーン

スコア・生存時間・撃破数を表示し、リトライを待ちます。

---

## `vampire_survivor/spawn_system.ex` — ウェーブスポーン

経過時間に応じてウェーブ定義から敵をスポーンします。

### ウェーブ定義

```mermaid
timeline
    title ウェーブスポーンスケジュール
    0秒   : Phase 1（3体 / 3000ms）: Slime
    30秒  : Phase 2（5体 / 2500ms）: Slime + Bat
    60秒  : Phase 3（7体 / 2000ms）: Bat + Golem
    120秒 : Phase 4（10体 / 1500ms）: 全種混合
    180秒 : Phase 5（15体 / 1000ms）: 全種混合（高密度）
```

| フェーズ | 開始時間 | スポーン間隔 | 1 回の数 | 敵種別 |
|:---|:---|:---|:---|:---|
| 1 | 0 秒 | 3,000ms | 3 体 | Slime |
| 2 | 30 秒 | 2,500ms | 5 体 | Slime + Bat |
| 3 | 60 秒 | 2,000ms | 7 体 | Bat + Golem |
| 4 | 120 秒 | 1,500ms | 10 体 | 全種混合 |
| 5 | 180 秒 | 1,000ms | 15 体 | 全種混合（高密度） |

### エリート敵

- **条件**: 45 秒以降、30% の確率で混入
- **効果**: HP × 3（`spawn_elite_enemy/4` を使用）

### 上限

- 最大同時存在数: **10,000 体**

---

## `vampire_survivor/boss_system.ex` — ボス出現スケジュール

経過時間に応じてボスの出現を管理します。

```mermaid
timeline
    title ボス出現スケジュール
    180秒（3分） : Slime King（HP 1,000）
    360秒（6分） : Bat Lord（HP 2,000）
    540秒（9分） : Stone Golem（HP 5,000）
```

---

## `vampire_survivor/level_system.ex` — 武器選択肢生成

レベルアップ時に提示する武器選択肢を生成します。

### ルール

1. **未所持武器を優先**（新規取得を促す）
2. **低レベル順でソート**（アップグレードを促す）
3. **最大 3 択**を返す
4. 全武器が最大レベル（Lv8）の場合は空リストを返す

### 武器スロット制限

- **最大スロット数**: 8
- **各武器の最大レベル**: 8

---

## EXP・レベルアップ曲線

```
Level → 必要累積 EXP
  1  →    0
  2  →   10
  3  →   25
  4  →   45
  5  →   70
  6  →  100
  7  →  135
  8  →  175
  9  →  220
 10  →  270
 ...
```

---

## アイテムシステム

| アイテム | 効果 |
|:---|:---|
| Gem | EXP 取得（敵撃破時にドロップ） |
| Potion | HP +20 回復 |
| Magnet | 画面内全 Gem を自動吸引 |

**自動収集範囲**: プレイヤー周囲 50px（Magnet 発動時は全画面）

---

## 将来の拡張予定

`game_network` アプリケーションは現在スタブ状態ですが、以下の機能が計画されています：

- Phoenix Channels によるリアルタイムマルチプレイヤー
- UDP による低遅延ゲーム状態同期
- ルームベースのマッチメイキング

---

## 関連ドキュメント

- [アーキテクチャ概要](./architecture-overview.md)
- [Elixir レイヤー詳細](./elixir-layer.md)
- [Rust レイヤー詳細](./rust-layer.md)
- [データフロー・通信](./data-flow.md)
