# AlchemyEngine — 残課題・懸念点

> `vision.md` が定義する Engine / World / Rule の 3 層分離を完成させることが最終目標。
> このドキュメントは未解決の課題と将来への懸念点を管理する。
> 課題が解消されたら該当セクションを削除すること。

---

## 課題一覧

### 課題6: `RuleBehaviour` に `initial_weapons/0` コールバックを追加する

**優先度**: 高（Engine / Rule 分離の原則に直接関わる）

**背景**

ゲーム開始時の初期武器は `Playing.init/1` の `weapon_levels: %{magic_wand: 1}` として定義されているが、
Rust 側の `weapon_slots` への追加は `GameEvents.init/1` が `Playing.init` の戻り値を直接参照することで行っている。
これは `game_engine` が `game_content` の内部実装に依存しており、Engine / Rule の分離原則に反する。

**目標**

`RuleBehaviour` に `initial_weapons/0` コールバックを追加し、`GameEvents.init/1` はそのコールバックを通じて初期武器を取得する。

```elixir
# RuleBehaviour に追加
@callback initial_weapons() :: [atom()]

# VampireSurvivorRule での実装例
def initial_weapons, do: [:magic_wand]

# GameEvents.init/1 での使用（現在の Playing.init 参照を置き換える）
Enum.each(rule.initial_weapons(), fn weapon_name ->
  if weapon_id = weapon_registry[weapon_name] do
    GameEngine.NifBridge.add_weapon(world_ref, weapon_id)
  end
end)
```

**影響ファイル**

- `apps/game_engine/lib/game_engine/rule_behaviour.ex` — `@callback initial_weapons() :: [atom()]` を追加
- `apps/game_content/lib/game_content/vampire_survivor_rule.ex` — `@impl` 実装を追加
- `apps/game_engine/lib/game_engine/game_events.ex` — `init/1` の初期武器追加ロジックを `rule.initial_weapons()` 経由に変更

---

### 課題7: `GameContent.EntityParams` のハードコード参照を `RuleBehaviour` コールバックに移行する

**優先度**: 中

**背景**

`game_events.ex` の `apply_event` 内で `GameContent.EntityParams.enemy_exp_reward/1`、
`GameContent.EntityParams.boss_exp_reward/1`、`GameContent.EntityParams.score_from_exp/1` が
直接呼ばれており、コンパイル時に警告が出ている（アンブレラの依存順序の問題）。
これらは Rule 固有のロジックであり、`game_engine` が `game_content` に直接依存すべきではない。

**目標**

`RuleBehaviour` にコールバックを追加し、`GameEvents` はそれを通じて報酬計算を委譲する。

```elixir
# RuleBehaviour に追加
@callback entity_exp_reward(entity_kind :: non_neg_integer()) :: non_neg_integer()
@callback score_from_exp(exp :: non_neg_integer()) :: non_neg_integer()

# GameEvents での使用
exp = rule.entity_exp_reward(enemy_kind)
score_delta = rule.score_from_exp(exp)
```

**影響ファイル**

- `apps/game_engine/lib/game_engine/rule_behaviour.ex`
- `apps/game_content/lib/game_content/vampire_survivor_rule.ex`
- `apps/game_engine/lib/game_engine/game_events.ex`

---

### 課題8: Rust の `GameWorldInner` からルール固有フィールドを除去する

**優先度**: 低（2つ目のコンテンツを作り始めるタイミングで実施）

**背景**

`vision.md` の「目指す姿」に記載の通り、現在の `GameWorldInner` には
`weapon_slots`、`boss`、`hud_level`、`hud_exp`、`hud_exp_to_next`、`hud_level_up_pending`、`hud_weapon_choices`
といった VampireSurvivor 固有のフィールドが残っている。
これらはエンジンが知るべき概念ではなく、Rule 側で管理されるべきものだ。

**目標**

- `weapon_slots` → Elixir 側 Rule state で管理し、Rust には `add_weapon` NIF 経由でのみ反映
- `boss` → Elixir 側 Rule state で管理し、Rust には `spawn_boss` NIF 経由でのみ反映
- `hud_*` フィールド群 → `set_hud_level_state` NIF の引数として毎フレーム注入する形に統一

**影響ファイル**

- `native/game_simulation/src/world/mod.rs` — `GameWorldInner` のフィールド整理
- `native/game_nif/src/render_snapshot.rs` — HUD データ取得方法の変更
- `apps/game_engine/lib/game_engine/game_events.ex` — 毎フレームの状態注入ロジック

---

## 新しいコンテンツを追加する際の手順

2つ目のコンテンツを追加する場合は、以下の手順に従うこと。

1. `WorldBehaviour` を実装した新モジュールを作成し、`setup_world_params/1` で `set_entity_params` NIF に `FirePattern` ベースの武器パラメータを注入する
2. `RuleBehaviour` を実装した新モジュールを作成する（`initial_weapons/0` を含む）
3. `config :game_server, current_world: NewWorld, current_rule: NewRule` を設定する

---

*このドキュメントは `vision.md` の思想に基づいて管理すること。*
