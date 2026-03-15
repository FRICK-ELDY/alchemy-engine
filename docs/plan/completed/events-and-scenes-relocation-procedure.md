# Events / Scenes 配置移行 実施手順書

> 作成日: 2026-03-15  
> **実施済み**: Phase 1（GameEvents → Contents.Events.Game）・Phase 2（SceneStack → Contents.Scenes.Stack）完了。  
> 目的: コンテンツ全体に関わる「イベント配送」と「シーンスタック」を `contents/` 配下から上位の `events/` と `scenes/` に移動し、責務の所在を明確にする。  
> 結果として「Elixir と Event の紐づけは events が担う」「シーン管理は scenes が担う」と分かりやすくなる。

---

## 1. 概要

### 1.1 移行先とモジュール名


| 現状                                                      | 移行後（パス）                                        | 移行後（モジュール名）                        |
| ------------------------------------------------------- | ---------------------------------------------- | ---------------------------------- |
| `apps/contents/lib/contents/game_events.ex`             | `apps/contents/lib/events/game.ex`             | `Contents.Events.Game`             |
| `apps/contents/lib/contents/game_events/diagnostics.ex` | `apps/contents/lib/events/game/diagnostics.ex` | `Contents.Events.Game.Diagnostics` |
| `apps/contents/lib/contents/scene_stack.ex`             | `apps/contents/lib/scenes/stack.ex`            | `Contents.Scenes.Stack`            |


- **GameEvents → Contents.Events.Game**: 「Events」が二重にならないよう `Game` にリネームする。
- **SceneStack → Contents.Scenes.Stack**: シーン管理のスタックであることがパスと名前の両方で分かるようにする。

### 1.2 変更対象の依存関係

- **起動・設定**: `Server.Application` の子仕様、`config :server, :game_events_module`
- **Content 契約**: `flow_runner/1` の doc や `event_handler/1` の doc で「SceneStack」「GameEvents」に言及している箇所
- **全参照**: `Contents.GameEvents` / `Contents.GameEvents.Diagnostics` / `Contents.SceneStack` を利用しているモジュール

---

## 2. 実施手順

### Phase 1: GameEvents → Contents.Events.Game

#### Step 1-1: ディレクトリとファイルの作成

- `apps/contents/lib/events/` を作成する。
- `apps/contents/lib/contents/game_events.ex` の内容を `apps/contents/lib/events/game.ex` にコピーする。
- 先頭のモジュール名を `defmodule Contents.Events.Game do` に変更する。
- ファイル内の `Contents.GameEvents.Diagnostics` を `Contents.Events.Game.Diagnostics` に変更する（alias および呼び出し）。
- `apps/contents/lib/contents/game_events/diagnostics.ex` の内容を `apps/contents/lib/events/game/diagnostics.ex` にコピーする。
- 先頭のモジュール名を `defmodule Contents.Events.Game.Diagnostics do` に変更する。
- ログメッセージ等で `[GameEvents]` としている箇所は、必要に応じて `[Events.Game]` に変更する（任意。一貫性のため推奨）。

#### Step 1-2: 設定の更新

- **config/config.exs**: `config :server, :game_events_module, Contents.GameEvents` を `config :server, :game_events_module, Contents.Events.Game` に変更する。
- **docs/architecture/** 内で `Contents.GameEvents` や `game_events_module` を説明している箇所があれば、同様に `Contents.Events.Game` に合わせて更新する。

#### Step 1-3: 参照の一括置換

- コードベースで `Contents.GameEvents` を検索し、`Contents.Events.Game` に置換する。
  - 対象: `Core.InputHandler` の doc、`Core.RoomRegistry` / `Core.RoomSupervisor` の doc、`Core.FormulaStore` の doc、各コンテンツ・コンポーネントの doc、`apps/network` 内のコメント、`Contents.Behaviour.Content` の doc など。
- `Contents.GameEvents.Diagnostics` を検索し、`Contents.Events.Game.Diagnostics` に置換する。
  - 対象: `Contents.Events.Game`（game.ex）内の alias、および Diagnostics を参照している箇所（通常は game.ex 内のみ）。

#### Step 1-4: 旧ファイルの削除

- `apps/contents/lib/contents/game_events.ex` を削除する。
- `apps/contents/lib/contents/game_events/diagnostics.ex` を削除する。
- `apps/contents/lib/contents/game_events/` ディレクトリが空になれば削除する。

#### Step 1-5: コンパイル・動作確認

- `mix compile` が通ることを確認する。
- 必要に応じて `config :server, :current` で指定しているコンテンツで起動し、イベント配送とシーン遷移が問題ないことを確認する。

---

### Phase 2: SceneStack → Contents.Scenes.Stack

#### Step 2-1: ディレクトリとファイルの作成

- `apps/contents/lib/scenes/` が存在しない場合は作成する（既に `scenes/` や `scenes/.gitkeep` がある場合はそのまま利用する）。
- `apps/contents/lib/contents/scene_stack.ex` の内容を `apps/contents/lib/scenes/stack.ex` にコピーする。
- 先頭のモジュール名を `defmodule Contents.Scenes.Stack do` に変更する。
- ファイル内の `@moduledoc` やコメントで `Contents.SceneStack` としている例があれば、`Contents.Scenes.Stack` に変更する。
- `default_server/0` のコメントで「Phase 1: 単一 SceneStack」等としている場合は、「単一 Stack」や「Contents.Scenes.Stack」に合わせて修正する（任意）。

#### Step 2-2: Application の更新

- **apps/server/lib/server/application.ex**: 子リスト内の `{Contents.SceneStack, [content_module: content]}` を `{Contents.Scenes.Stack, [content_module: content]}` に変更する。

#### Step 2-3: Content の flow_runner 更新

- 各 Content で `Process.whereis(Contents.SceneStack)` としている箇所を `Process.whereis(Contents.Scenes.Stack)` に変更する。
  - 対象: `Content.FormulaTest`, `Content.VampireSurvivor`, `Content.CanvasTest`, `Content.RollingBall`, `Content.SimpleBox3D`, `Content.BulletHell3D`, `Content.AsteroidArena` 等。

#### Step 2-4: コンポーネント・Game 内の参照更新

- `Contents.SceneStack` を検索し、`Contents.Scenes.Stack` に一括置換する。
  - 対象: 各コンテンツの InputComponent / RenderComponent / LevelComponent / BossComponent / PhysicsComponent、`Contents.Events.Game`（旧 GameEvents）内の `GenServer.call(runner, ...)` の runner が指すプロセス、VampireSurvivor の BossAlert シーンなど。
- **alias を使用している場合**: `alias Contents.SceneStack` を `alias Contents.Scenes.Stack` に変更し、呼び出しを `SceneStack.xxx` から `Stack.xxx` に変更する（モジュール名が `Stack` のため）。  
  - または `alias Contents.Scenes.Stack, as: SceneStack` として、既存の `SceneStack.xxx` 呼び出しをそのまま残すこともできる（手順書では「as: SceneStack」で揃えてもよい）。

#### Step 2-5: 契約・ドキュメントの更新

- **Contents.Behaviour.Content**: `scene_stack_spec/1` や `flow_runner/1` の `@doc` で「SceneStack」に言及している箇所を「Contents.Scenes.Stack」または「シーンスタック」に合わせて更新する。
- **Contents.Behaviour.Scenes**（存在する場合）: SceneStack との連携説明を `Contents.Scenes.Stack` に合わせる。
- **Contents.SceneBehaviour**（存在する場合）: 同様に doc 内の SceneStack 参照を `Contents.Scenes.Stack` に合わせる。

#### Step 2-6: 旧ファイルの削除

- `apps/contents/lib/contents/scene_stack.ex` を削除する。

#### Step 2-7: コンパイル・動作確認

- `mix compile` が通ることを確認する。
- 起動してシーンスタックの push/replace/update が問題ないことを確認する。

---

## 3. 参照一覧（置換時の目安）

### Contents.GameEvents → Contents.Events.Game

- `config/config.exs`: `game_events_module`
- `apps/contents/lib/contents/game_events.ex` → 削除（移行後は `events/game.ex`）
- `apps/contents/lib/contents/game_events/diagnostics.ex` → 削除（移行後は `events/game/diagnostics.ex`）
- 上記以外で「Contents.GameEvents」を参照しているコード・ドキュメントは検索で洗い出し、`Contents.Events.Game` に置換する。

### Contents.GameEvents.Diagnostics → Contents.Events.Game.Diagnostics

- 主に `Contents.Events.Game`（game.ex）内の alias と、他に Diagnostics を直接参照している箇所があれば置換する。

### Contents.SceneStack → Contents.Scenes.Stack

- `apps/server/lib/server/application.ex`: 子仕様
- 各 Content の `flow_runner/1`
- 各コンポーネントの `Contents.SceneStack.xxx` / `SceneStack.xxx` 呼び出し
- `Contents.Events.Game` 内の `GenServer.call(runner, ...)` の runner が指すプロセスは「SceneStack の pid」のままなので、モジュール名の置換のみでよい（flow_runner が返す pid は Contents.Scenes.Stack の登録名で取得するため、Content の flow_runner を Step 2-3 で更新すればよい）。
- Behaviour / SceneBehaviour の doc

---

## 4. 注意事項

- **Phase 1 と Phase 2 の順序**: 先に GameEvents → Events.Game を実施し、その後 SceneStack → Scenes.Stack を実施することを推奨する。同時に実施してもよいが、参照が多く分離した方が差分確認が容易である。
- **alias の扱い**: `Contents.Scenes.Stack` を `alias Contents.Scenes.Stack, as: SceneStack` とすると、既存の `SceneStack.current(runner)` 等の呼び出しをそのまま残せる。`as:` を付けずに `Stack` とする場合は、呼び出しをすべて `Stack.xxx` に変更する必要がある。**実施前にどちらとするか検討すること**（一貫性・可読性・変更量のバランスを考慮する）。
- **他プランとの整合**: `scene-type-as-atom-implementation-procedure.md` 等で「Contents.SceneStack」「Contents.GameEvents」と記載している箇所があれば、本手順完了後に「Contents.Scenes.Stack」「Contents.Events.Game」に読み替えるか、手順書内を更新する。
