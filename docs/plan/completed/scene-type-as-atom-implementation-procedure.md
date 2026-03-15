# 案B: シーン種別＝atom・実装＝コンテンツ 実施手順書

> 作成日: 2026-03-15  
> 参照: [scene-abstraction-and-engines.md](../current/scene-abstraction-and-engines.md) 案B, [scene-and-object.md](../../../architecture/scene-and-object.md), [contents-migration-plan.md](../current/contents-migration-plan.md)  
> 目的: シーンを「モジュール」ではなく**種別（atom）**で扱い、**コンテンツ**が `scene_init/2` / `scene_update/3` / `scene_render_type/1` で実装する方式に移行する。  
> 結果として「Contents.Scenes.Playing」は概念（`:playing`）としてのみ存在し、`Content.VampireSurvivor` 等が「:playing をこう実装する」と明確になる。

---

## 1. 概要

### 1.1 案Bの定義

| 項目 | 現状 | 案B 移行後 |
|------|------|------------|
| **シーンの識別** | モジュール（例: `Content.FormulaTest.Scenes.Playing`） | 種別（atom）`:playing`, `:title`, `:game_over`, `:level_up`, `:boss_alert` 等 |
| **init** | `module.init(init_arg)` | `content.scene_init(scene_type, init_arg)` |
| **update** | `module.update(context, state)` | `content.scene_update(scene_type, context, state)` |
| **render_type** | `module.render_type()` | `content.scene_render_type(scene_type)` |
| **スタック要素** | `%{module: module(), state: term()}` | `%{scene_type: atom(), state: term()}` |
| **initial_scenes** | `[%{module: M, init_arg: map()}]` | `[%{scene_type: atom(), init_arg: map()}]` |
| **playing_scene / game_over_scene 等** | `scene_module()` を返す | `scene_type()`（atom）を返す |
| **get_scene_state / update_by_*** のキー** | モジュール | scene_type（atom） |

### 1.2 変更対象モジュール・ファイル

| 対象 | 変更内容 |
|------|----------|
| **Content 契約**（未実施時: `Core.ContentBehaviour`。`contents-behaviour-namespace-implementation-plan` 実施後: `Contents.Behaviour.Content`） | 新コールバック `scene_init/2`, `scene_update/3`, `scene_render_type/1` 追加。`initial_scenes/0` の仕様変更、`playing_scene/0` / `game_over_scene/0` 等の返却型を `scene_type()` に。`physics_scenes/0` を `[scene_type()]` に（任意）。オプショナル: シーン固有データ用（例: `weapon_slots_for_nif/2`）はコンテンツ直下のオプショナルコールバックとして明文化。 |
| **Contents.SceneStack** | スタックを `%{scene_type, state}` に変更。`init_scene` を `content.scene_init(type, arg)` に。`get_scene_state(server, module)` → `get_scene_state(server, scene_type)`。`update_by_module` → `update_by_scene_type(server, scene_type, fun)`。push/replace の引数を `(scene_type, init_arg)` に。 |
| **Contents.GameEvents** | `:current` の返却を `%{scene_type: type, state: state}` に合わせる。`mod.update` を `content.scene_update(scene_type, context, state)` に変更。`process_transition` で `{:replace, scene_type, init_arg}` 等を処理。`build_context` の `push_scene` / `replace_scene` を `(scene_type, init_arg)` に。`physics_scenes` が `[scene_type()]` の場合の `mod in physics_scenes` を `scene_type in physics_scenes` に。 |
| **各 Content モジュール** | `initial_scenes` / `playing_scene` / `game_over_scene` 等を新仕様に。`scene_init` / `scene_update` / `scene_render_type` を実装。既存の `Content.XXX.Scenes.*` モジュールは削除するか、コンテンツの `scene_*` から委譲用に残す。 |
| **各 Component（Input/Render/Level/Boss 等）** | `Content.FormulaTest.Scenes.Playing` 等のモジュール参照をやめ、`content.playing_scene()`（`:playing`）を `get_scene_state` / `update_by_scene_type` に渡す。シーン固有の関数（例: `playing_scene.weapon_slots_for_nif`）は `content.weapon_slots_for_nif` 等のコンテンツコールバックに置き換える。 |

### 1.3 シーン種別（scene_type）の例

共通化のため、よく使う種別は atom で統一する。コンテンツが使わない種別は実装しなくてよい（未実装の type で scene_init が呼ばれたらエラーまたは optional でスキップ）。

| scene_type | 用途 | 実装例 |
|------------|------|--------|
| `:playing` | プレイ中 | FormulaTest, VampireSurvivor, RollingBall 等 |
| `:title` | タイトル | RollingBall, VampireSurvivor 等 |
| `:game_over` | ゲームオーバー | SimpleBox3D, BulletHell3D, VampireSurvivor 等 |
| `:level_up` | レベルアップ（武器選択） | VampireSurvivor |
| `:boss_alert` | ボス出現前アラート | VampireSurvivor |
| `:stage_clear` | ステージクリア | RollingBall |
| `:ending` | エンディング | RollingBall |

---

## 2. 実施手順

### Phase 1: 型・契約の定義（ContentBehaviour 拡張）

#### Step 1-1: scene_type の定義

- **場所**: Content 契約を定義しているモジュールの `@type` に `@type scene_type :: atom()` を追加。  
  - 未実施時: `Core.ContentBehaviour`（`apps/core/lib/core/content_behaviour.ex`）。  
  - `contents-behaviour-namespace-implementation-plan` 実施後: `Contents.Behaviour.Content`（`apps/contents/lib/behaviour/content.ex`）。  
- 必要なら「推奨シーン種別」を `@doc` で列挙（`:playing`, `:title`, `:game_over`, `:level_up`, `:boss_alert`, `:stage_clear`, `:ending`）。

#### Step 1-2: ContentBehaviour に必須コールバック追加

**ファイル:** `apps/core/lib/core/content_behaviour.ex`

> **注記**: [implementation-order-for-plans.md](../current/implementation-order-for-plans.md) の推奨どおり、先に `contents-behaviour-namespace-implementation-plan` を実施している場合は、このファイルはすでに `apps/contents/lib/behaviour/content.ex` に移っており、モジュール名は `Contents.Behaviour.Content` です。その場合は **ファイル:** `apps/contents/lib/behaviour/content.ex`（モジュール `Contents.Behaviour.Content`）に以下を追加してください。

- 次のコールバックを追加する。

```elixir
@doc """
シーン種別ごとの初期化。返却 state には root_object を含めることを推奨（新規・将来コンテンツ）。
"""
@callback scene_init(scene_type(), init_arg :: term()) :: {:ok, state :: term()}

@doc """
シーン種別ごとの update。戻り値は SceneBehaviour の update と同様（{:continue, state} または {:transition, ...}）。
"""
@callback scene_update(scene_type(), context :: map(), state :: term()) ::
  {:continue, state :: term()}
  | {:continue, state :: term(), opts :: map()}
  | {:transition, :pop, state :: term()}
  | {:transition, :pop, state :: term(), opts :: map()}
  | {:transition, {:push, scene_type(), init_arg :: term()}, state :: term()}
  | {:transition, {:push, scene_type(), init_arg :: term()}, state :: term(), opts :: map()}
  | {:transition, {:replace, scene_type(), init_arg :: term()}, state :: term()}
  | {:transition, {:replace, scene_type(), init_arg :: term()}, state :: term(), opts :: map()}

@doc """
シーン種別ごとの描画種別（例: :playing, :title）。
"""
@callback scene_render_type(scene_type()) :: atom()
```

- `@type scene_type :: atom()` を同じファイルで定義する。

#### Step 1-3: ContentBehaviour の既存コールバック仕様変更

- **対象ファイル**: Step 1-2 と同様。`contents-behaviour-namespace-implementation-plan` 実施後は `Contents.Behaviour.Content`（`apps/contents/lib/behaviour/content.ex`）。
- `@callback initial_scenes() :: [%{module: scene_module(), init_arg: map()}]`  
  → `@callback initial_scenes() :: [%{scene_type: scene_type(), init_arg: map()}]`
- `@callback playing_scene() :: scene_module()`  
  → `@callback playing_scene() :: scene_type()`
- `@callback game_over_scene() :: scene_module()`  
  → `@callback game_over_scene() :: scene_type()`
- `@callback physics_scenes() :: [scene_module()]`  
  → `@callback physics_scenes() :: [scene_type()]`
- オプショナル: `level_up_scene/0`, `boss_alert_scene/0` の返却型を `scene_type()` に。  
- オプショナル: `pause_on_push?(scene_module())` → `pause_on_push?(scene_type())`。

※ この時点では「型とコールバックの追加・仕様記載」まで。実装は Phase 4 でコンテンツごとに行う。

---

### Phase 2: SceneStack の変更

#### Step 2-1: スタック要素の形式変更

- 現在: `%{module: module(), state: term()}`
- 変更後: `%{scene_type: scene_type(), state: term()}`

`init` で `content_module.initial_scenes()` を取得し、各要素を `%{scene_type: type, init_arg: arg}` と解釈。  
`init_scene(content, scene_type, init_arg)` で `content.scene_init(scene_type, init_arg)` を呼び、`{:ok, state}` を受け取り `%{scene_type: scene_type, state: state}` をスタックに積む。

#### Step 2-2: init_scene のシグネチャ変更

- 現在: `init_scene(module, init_arg)` → `module.init(init_arg)`
- 変更後: `init_scene(content, scene_type, init_arg)` を追加（または init 内で直接呼ぶ）。  
  `content.scene_init(scene_type, init_arg)` を呼び、`{:ok, scene_state}` から `%{scene_type: scene_type, state: scene_state}` を返す。  
  SceneStack の state に `content_module` は既にあるので、`init` / push / replace では `content_module` を使って `scene_init` を呼ぶ。

#### Step 2-3: current / render_type の返却

- `handle_call(:current, ...)`: 返却を `{:ok, %{scene_type: type, state: state}}` に。  
  （後方互換が必要なら `%{module: ..., state: ...}` をやめ、呼び出し側を一括で `scene_type` 対応にする。）
- `handle_call(:render_type, ...)`: `content.scene_render_type(top.scene_type)` を返す。

#### Step 2-4: push / replace の引数

- `handle_call({:push, module, init_arg}, ...)` → `handle_call({:push, scene_type, init_arg}, ...)`  
  `init_scene(content, scene_type, init_arg)` で初期化し、`%{scene_type: scene_type, state: state}` をスタックに push。
- `handle_call({:replace, module, init_arg}, ...)` → `handle_call({:replace, scene_type, init_arg}, ...)`  
  同様に `scene_type` で初期化して replace。

#### Step 2-5: get_scene_state / update_by_* の API 変更

- `get_scene_state(server, module)` → `get_scene_state(server, scene_type)`  
  スタックから `scene_type` が一致する要素を検索し、その `state` を返す。複数ある場合は先頭（または仕様で規定）のものを返す。
- `update_by_module(server, module, fun)` → `update_by_scene_type(server, scene_type, fun)`  
  `scene_type` が一致する要素の `state` に `fun` を適用し、スタックを更新する。  
  後方互換のため `update_by_module` を残す場合は、内部で `content.playing_scene()` 等から scene_type を解決するのではなく、呼び出し側を `update_by_scene_type` に寄せることを推奨。

#### Step 2-6: update_current の扱い

- 現状のまま。トップの `state` を `fun.(top.state)` で更新。トップのキーは `scene_type` になる。

---

### Phase 3: GameEvents の変更

#### Step 3-1: handle_frame_events_main_dispatch の引数

- 現在: `{:ok, %{module: mod, state: scene_state}}`
- 変更後: `{:ok, %{scene_type: scene_type, state: scene_state}}`

`content` は opts から取得済み。`mod.update(context, scene_state)` を `content.scene_update(scene_type, context, scene_state)` に変更する。

#### Step 3-2: process_transition の遷移表現

- 現在: `{:transition, {:push, mod, init_arg}, state}` / `{:transition, {:replace, mod, init_arg}, state}`
- 変更後: `{:transition, {:push, scene_type, init_arg}, state}` / `{:transition, {:replace, scene_type, init_arg}, state}`

`GenServer.call(runner, {:push, mod, init_arg})` を `GenServer.call(runner, {:push, scene_type, init_arg})` に。replace も同様。  
`Diagnostics.build_replace_init_arg` 等で `mod` を使っている場合は、引数を `scene_type` に変更し、必要なら content 経由で init_arg を補完する。

#### Step 3-3: build_context の push_scene / replace_scene

- 現在: `push_scene: fn mod, init_arg -> GenServer.call(runner, {:push, mod, init_arg}) end`
- 変更後: `push_scene: fn scene_type, init_arg -> GenServer.call(runner, {:push, scene_type, init_arg}) end`  
  `replace_scene` も同様。`pause_on_push?` の引数が `scene_type` になるため、content 側の実装を `pause_on_push?(scene_type)` に合わせる。

#### Step 3-4: physics_scenes の利用箇所

- `maybe_set_input_and_broadcast(state, mod, physics_scenes, ...)` で `mod in physics_scenes` としている箇所を、  
  `scene_type in physics_scenes` に変更。渡すのは `opts` の `scene_type`（または current から取得した scene_type）。

---

### Phase 4: コンテンツ・コンポーネントの移行

#### Step 4-1: FormulaTest の移行（先に実施推奨）

1. **Content.FormulaTest**
   - `initial_scenes/0`: `[%{module: Content.FormulaTest.Scenes.Playing, init_arg: %{}}]`  
     → `[%{scene_type: :playing, init_arg: %{}}]`
   - `playing_scene/0`: `Content.FormulaTest.Scenes.Playing` → `:playing`
   - `game_over_scene/0`: 同様に `:playing`
   - `physics_scenes/0`: 現状 `[]` のまま（`[]` でよい）。

2. **scene_init(:playing, init_arg)**
   - 現在の `Content.FormulaTest.Scenes.Playing.init/1` の内容を、`Content.FormulaTest` に `scene_init(:playing, init_arg)` として実装。  
     （root_object 構築・formula_results 計算・state の形はそのまま。）

3. **scene_update(:playing, context, state)**
   - 現在の `Playing.update/2` の内容を、`Content.FormulaTest.scene_update(:playing, context, state)` に移す。  
     現在は `{:continue, state}` のみでよい。

4. **scene_render_type(:playing)**
   - `:playing` を返す。

5. **InputComponent / RenderComponent**
   - `Contents.SceneStack.get_scene_state(runner, content.playing_scene())` → そのまま（`content.playing_scene()` が `:playing` を返すため、SceneStack は `get_scene_state(runner, :playing)` と同等で動作する）。
   - `Contents.SceneStack.update_by_module(runner, Content.FormulaTest.Scenes.Playing, fun)`  
     → `Contents.SceneStack.update_by_scene_type(runner, :playing, fun)` または `update_by_scene_type(runner, content.playing_scene(), fun)`。

6. **旧シーンモジュール**
   - `Content.FormulaTest.Scenes.Playing`（`apps/contents/lib/contents/formula_test/scenes/playing.ex`）は削除する。  
     または、移行期間中は `Content.FormulaTest` の `scene_*` がそのモジュールに委譲する形で残し、後で削除してもよい。

#### Step 4-2: 他コンテンツの移行順序と方針

| コンテンツ | 主なシーン種別 | 備考 |
|------------|----------------|------|
| CanvasTest | `:playing` | 同上のパターンで scene_init/update/render_type を実装。 |
| SimpleBox3D | `:playing`, `:game_over` | 遷移は `{:replace, :playing, %{}}` / `{:replace, :game_over, %{}}`。 |
| BulletHell3D | `:playing`, `:game_over` | 同様。 |
| AsteroidArena | `:playing`, `:game_over` | 同様。 |
| RollingBall | `:title`, `:playing`, `:stage_clear`, `:game_over`, `:ending` | 遷移が多い。各 type で scene_init/update/render_type を実装。 |
| VampireSurvivor | `:playing`, `:game_over`, `:level_up`, `:boss_alert` 等 | `level_up_scene/0`, `boss_alert_scene/0` を `:level_up`, `:boss_alert` に。`weapon_slots_for_nif` 等は Content のオプショナルコールバックとして呼び出し元を `content.weapon_slots_for_nif(...)` に変更。 |

各コンテンツで行うことの共通パターン:

1. `initial_scenes` を `[%{scene_type: atom(), init_arg: map()}]` に変更。
2. `playing_scene` / `game_over_scene` / `level_up_scene` / `boss_alert_scene` を atom で返すように変更。
3. `scene_init(type, arg)` / `scene_update(type, ctx, state)` / `scene_render_type(type)` を実装（必要な type のみ）。
4. 既存の `Content.XXX.Scenes.*` モジュールは削除するか、上記コールバックから委譲するだけにしてから削除。
5. コンポーネント内の `get_scene_state(runner, content.playing_scene())` はそのままでよい。`update_by_module(runner, content.playing_scene(), fun)` を `update_by_scene_type(runner, content.playing_scene(), fun)` に変更。
6. `Content.XXX.Scenes.Playing` のようなモジュールを直接参照している箇所（例: `Content.VampireSurvivor.Scenes.Playing`）は、`content.playing_scene()` で得た scene_type を使うか、必要なら `content` の別コールバック（例: `weapon_slots_for_nif`）に置き換える。

#### Step 4-3: シーン固有の関数呼び出し（VampireSurvivor 等）

- 現在: `content.playing_scene().weapon_slots_for_nif(...)` や `content.playing_scene().accumulate_exp(...)` のように、シーンモジュールの関数を呼んでいる箇所がある。
- 案Bでは「シーン＝モジュール」がないため、これらは **コンテンツのオプショナルコールバック** にする。
  - 例: `Content.VampireSurvivor.weapon_slots_for_nif(weapon_levels, weapon_cooldowns)`  
  - 例: `Content.VampireSurvivor.accumulate_exp(state, exp)`  
- ContentBehaviour に `@optional_callbacks` で追加するか、既存のオプショナルコールバックとして doc を足し、呼び出し元（LevelComponent, BossComponent 等）で `function_exported?(content, :weapon_slots_for_nif, 2)` でガードして呼ぶ。

---

### Phase 5: 診断・その他参照の更新

#### Step 5-1: GameEvents.Diagnostics

- `get_playing_scene_state(content, runner)`: 現在 `GenServer.call(runner, {:get_scene_state, content.playing_scene()})`。  
  SceneStack が `get_scene_state(server, scene_type)` を受け付けるなら、`content.playing_scene()` が `:playing` を返すため、そのままでよい（GenServer のメッセージが `{:get_scene_state, :playing}` に変わるだけ）。

#### Step 5-2: NIF / Load 等での GenServer メッセージ

- `game_events.ex` 内の `GenServer.call(runner, {:replace, physics_scene, initial_state})` のように、既存で `module` を渡している箇所があれば、`scene_type` と init_arg に合わせて変更。  
  （ロード時は「Playing を特定の state で置き換える」なら `{:replace, :playing, initial_state}` のような形にする。SceneStack が replace で `init_arg` を state として扱うか、`scene_init(:playing, initial_state)` を呼ぶかは仕様で決める。通常は `scene_init` を通すと state が再計算されるため、ロード時は「既存 state をそのまま replace で上書き」する API が SceneStack に必要になる可能性がある。その場合は Step 2 で `{:replace_with_state, scene_type, state}` のような内部メッセージを検討する。）

---

## 3. 検証

### 3.1 コンパイル

```bash
mix compile --warnings-as-errors
```

### 3.2 起動・動作確認

- 各コンテンツで `config :server, :current, Content.XXX` を指定して起動。
- FormulaTest: HUD 表示、ESC / Quit、5 パターン結果表示。
- VampireSurvivor / RollingBall 等: シーン遷移、レベルアップ、ボスアラート、ゲームオーバー等が従来どおり動作すること。

### 3.3 チェックリスト

- [x] ContentBehaviour に scene_init / scene_update / scene_render_type が定義され、各コンテンツが実装している
- [x] SceneStack のスタックが `%{scene_type, state}` になり、push/replace/get_scene_state/update_by_scene_type が scene_type で動作する
- [x] GameEvents が content.scene_update(scene_type, ...) を呼び、遷移が scene_type で行われる
- [x] 既存のシーンモジュール参照（Content.XXX.Scenes.Playing 等）がコンテンツの scene_type またはコンテンツコールバックに置き換わっている
- [x] `mix compile --warnings-as-errors` が通り、代表コンテンツで手動動作確認が完了している

---

## 4. ロールバック・段階移行

- 一括移行の場合: 案B 導入前にブランチを切り、Phase 2〜4 を一気に実施したうえでテストする。
- 段階移行をする場合: SceneStack と GameEvents で「module 形式」と「scene_type 形式」の両方を許容し、`initial_scenes` の要素に `module` があれば従来の `module.init` / `module.update`、`scene_type` があれば `content.scene_*` を呼ぶ分岐を入れる。その場合、手順は Phase 2 の「両形式の解釈」から書き足す必要がある。本手順書では「案B に完全切り替え」を前提とする。

---

## 5. 参照

- [scene-abstraction-and-engines.md](../current/scene-abstraction-and-engines.md) — 案B の説明と他エンジン比較
- [formula-test-scene-migration-procedure.md](../current/formula-test-scene-migration-procedure.md) — 現方式での FormulaTest シーン移行（案B とは別経路）
- [scene-and-object.md](../../../architecture/scene-and-object.md) — Scene の責務と root_object
- [Contents.SceneStack](../../../apps/contents/lib/contents/scene_stack.ex) — 現行 SceneStack
- Content 契約: 未実施時は [Core.ContentBehaviour](../../../apps/core/lib/core/content_behaviour.ex)。[contents-behaviour-namespace-implementation-plan](./contents-behaviour-namespace-implementation-plan.md) 実施後は [Contents.Behaviour.Content](../../../apps/contents/lib/behaviour/content.ex)。
