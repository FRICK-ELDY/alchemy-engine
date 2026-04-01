# 実施計画: コンテンツ縮小（3 本維持）とゲーム系 NIF 撤去

## 前提

- **維持**: `Content.CanvasTest`, `Content.BulletHell3D`, `Content.FormulaTest`（およびそれぞれの `playing` / 付随シーン）。`FormulaTest` は Formula エンジン検証の**想定どおりの利用**を継続する。
- **削除**: `AsteroidArena`, `RollingBall`, `SimpleBox3D`, `VampireSurvivor`。
- **将来（本計画の削除対象外）**: `apps/contents/lib/contents/builtin` と `apps/contents/content_definitions` — コンテンツ爆増時の整理用。対の関係は `workspace/1_backlog/builtin-content-future.md` に記載。コード・ディレクトリは未着手でもよい。
- 本計画は **コンパイル・テスト・ローカル起動が通ること**を各フェーズの完了条件とする。

## フェーズ 0: インベントリ（着手前チェックリスト）

- [x] `rg` / IDE で削除モジュール名・シーンモジュールの参照を一覧化（`config/`、`apps/server/`、`apps/core/lib/core/config.ex`、`Contents.Scenes.Stack`、テスト、`docs/`）。
- [x] `builtin` について `workspace/1_backlog/builtin-content-future.md` を最新化し、将来の役割が一言で追える状態にする（アーキテクチャ overview 等へのリンク追記は任意）。
- [x] `Core.Formula.run/3` の呼び出し元を全列挙し、**FormulaTest 維持**に伴い `run_formula_bytecode` 等の経路をどう残すか（NIF 最小化 vs Elixir 化）を方針として 1 段落で書く。
- [x] `Contents.Events.Game` から**ゲーム ECS 系** NIF を外した後のフレーム駆動モデル（Elixir のみ tick、インジェクション経路の単純化）を 1 段落で方針化する。

### フェーズ 0 成果: 削除対象コンテンツ参照インベントリ（2026-04-01 時点）

調査コマンド例: `rg -i "AsteroidArena|RollingBall|SimpleBox3D|VampireSurvivor" --glob "*.{ex,exs,md}"`

| 区分 | パス（代表） | 備考 |
|------|----------------|------|
| **実行時設定** | `config/config.exs` | `config :server, :current, Content.BulletHell3D`（フェーズ 1 完了後） |
| **デフォルトフォールバック** | `apps/core/lib/core/config.ex` | `@default_content Content.BulletHell3D` |
| **OTP 起動** | `apps/server/lib/server/application.ex` | `get_env(:server, :current, Content.BulletHell3D)`、`Scenes.Stack` の `content_module` |
| **ドキュメント例示** | `apps/contents/lib/scenes/stack.ex` | moduledoc の例は `Content.BulletHell3D` |
| **パッケージ説明** | `apps/contents/lib/contents.ex`, `apps/contents/README.md` | 一覧・説明文の更新が必要 |
| **ゲームイベント** | `apps/contents/lib/events/game.ex` | VampireSurvivor 向けコメント・分岐（フェーズ 2） |
| **テスト** | `apps/contents/test/content/` | VS 専用 7 ファイルはフェーズ 1 で削除済み。`component_list_test.exs` は `Content.BulletHell3D` を使用 |
| **ドキュメント（履歴・設計）** | `docs/architecture/elixir/contents.md`, `overview.md`, `contents/vampire_survivor.md`, `evaluation/*`, `workspace/7_done/*` 等 | フェーズ 1 のコード削除後に追随更新するか、履歴として残すかは別判断。**フェーズ 1 のブロッカーではない** |
| **削除済み実装本体** | （同上ディレクトリ・トップ `*.ex`） | フェーズ 1 で削除済み |

### フェーズ 0 成果: `Core.Formula.run/3` と `run_formula_bytecode`（方針・1 段落）

`NifBridge.run_formula_bytecode/3` を呼ぶのは **`apps/core/lib/core/formula.ex` のみ**。`Core.Formula.run/3` の呼び出しは **`Core.FormulaGraph`**（グラフ実行）と **`apps/core/test/core/formula_test.exs`**（単体テスト）、および `formula.ex` の moduledoc 例示に限られる。一方 **`Content.FormulaTest`** のプレイ中検証は **`Contents.Nodes.Test.Formula.run/0`**（Nodes の `handle_sample`）であり、**現行パスでは `Core.Formula.run` を経由しない**。したがって FormulaTest を残しても「Nodes 検証」と「bytecode + NIF」の責務は分離されている。**フェーズ 3 ではゲーム ECS 用 NIF を削減しつつ、`run_formula_bytecode` は `Core.Formula` / `FormulaGraph` / core テストのためにクレート内で切り離して維持する**方針とする。純 Elixir VM への置換は必須ではなく、NIF スリム化後の後続タスクとする。

### フェーズ 0 成果: `Contents.Events.Game` 撤去後のフレーム駆動（方針・1 段落）

現状、`Game` GenServer は **`Core.NifBridge.create_world` / `start_rust_game_loop` / `set_frame_injection_binary` / `set_player_input` / `pause_physics`・`resume_physics`** 等で Rust 側ゲームループと同期し、描画用バイナリを NIF 経由で送っている。**ゲーム ECS 系 NIF を外した後**は、ルーム・シーンスタック・コンポーネントの更新は **Elixir 上のメッセージ／タイマー駆動の tick のみ**で完結させ、`world_ref` や `control_ref` が不要なコンテンツでは **参照を持たないか nil 安全なスタブ**にする。クライアントへ届ける **`RenderFrame` 相当のバイナリ注入**は、Rust ゲームループに依存しない **単一の書き込み経路**（現行の `set_frame_injection_binary` と同等の契約を Elixir または残存ネイティブ層で満たす）に集約し、武器スロット・敵スポーン等 **VampireSurvivor 専用の NIF 呼び出しは削除**する。

## フェーズ 1: コンテンツ削除（Elixir）

- [x] **削除対象のみ**指定ディレクトリ・トップレベル `*.ex`（各 `Content.*`）を削除（`formula_test` は対象外）。
- [x] `apps/contents/test/content/` 以下の**削除コンテンツ専用**テストを削除またはスキップ理由をコメント（削除推奨）。
- [x] デフォルトコンテンツを `Content.CanvasTest` / `Content.BulletHell3D` / `Content.FormulaTest` のいずれかに統一（開発用途に応じて切替可能ならコメントで明記）:
  - `apps/core/lib/core/config.ex` の `@default_content`
  - `apps/server/lib/server/application.ex` の `:current`
  - `config/config.exs` のコメント・参照
  - `config/formula_test.exs` は **FormulaTest 用として維持**（`mix` の config パスから外さない）。削除コンテンツ専用 config のみ整理する。
- [x] `Contents.Scenes.Stack` の moduledoc 例を `Content.BulletHell3D` に更新（実行時は従来どおり `Application.get_env(:server, :current, ...)`）。
- [x] ルート `Content` の moduledoc（`apps/contents/lib/contents.ex`）を **維持 3 コンテンツ**に更新。

## フェーズ 2: 削除コンテンツ専用コンポーネント・イベントの整理

- [x] `Contents.Events.Game` 内の VampireSurvivor 向け分岐（例: 武器スロット注入フォールバック）を、残存コンテンツに不要なら削除。
- [x] `Contents.Events.Game.Diagnostics` の NIF メトリクス（敵弾数・SSoT チェック等）を、NIF 撤去方針に合わせて Elixir のみまたは削除。
- [x] `Contents.Components.Category.Spawner` が残存コンテンツで未使用なら削除、使用されていれば NIF 非依存の API に変更。（`BulletHell3D` が `world_size` のみ利用のため **維持**、moduledoc のみ整理）
- [x] `PhysicsEntity` 等、Asteroid / NIF 物理専用と分かるコンポーネントは参照ゼロ確認のうえ削除または doc のみ残す。（`PhysicsEntity` 削除。`Content.EntityParams` は参照ゼロのため削除）

## フェーズ 3: ゲーム系 NIF の撤去（Elixir 側）

- [ ] `world_ref` / `control_ref` を前提とした初期化・毎フレーム同期を、`game.ex` から排除またはスタブに置換（**CanvasTest / BulletHell3D / FormulaTest** の `build_frame` / 入力・式検証が動く経路に縮小）。
- [ ] `Core.NifBridge` から**ゲーム ECS 系**の `def` を削除し、**Formula 用**（`run_formula_bytecode` 等）とテスト用 Behaviour のみ残す方針を決めて実装する。完全に Rustler を外す場合は先に `Core.Formula` の純 Elixir 化が必要。
- [ ] `Core` のファサード（`apps/core/lib/core.ex`）から**ゲーム用** NIF 直叩き API を削除（Formula 用は残すか `Core.Formula` 経由に集約）。
- [ ] `Core.SaveManager` の NIF 連携を、セーブ機能を残す場合は Elixir スナップショットのみに変更。不要ならセーブ経路ごと縮小。
- [ ] `Core.Formula`: FormulaTest 維持のため、**当面は NIF 経路を維持**するか、移行完了後に純 Elixir のみとするかを決めて実装・テストを揃える。
- [ ] `config :core, Core.NifBridge, features: []` 等、NIF 関連設定を、残す API に合わせて整理（完全撤去時は削除）。
- [ ] `Mox` の `Core.NifBridgeMock` と、それに依存するテストを、残存 API に合わせて更新または削除。

## フェーズ 4: Rust / ワークスペース整理

- [ ] `native/nif` クレートから**ゲーム ECS・物理**関連を削除または別クレートへ分離し、ビルド対象を整理する。**Formula 実行**が NIF に残る場合は `nif` メンバー自体は維持し、中身のスリム化から着手する。
- [ ] `native/Cargo.toml` の `members` とクレート間依存を、上記方針に合わせて更新。
- [ ] CI / `mix compile` 手順の変更（Rustler の有無・ビルド時間）を README または開発メモに追記（任意）。

## フェーズ 5: 検証

- [ ] `mix test`（`apps/core`, `apps/contents` 中心）。
- [ ] サーバ起動し、`CanvasTest` / `BulletHell3D` / `FormulaTest` のシーン遷移・入力・描画（および Formula 検証表示）が従来通りであること。
- [ ] 削除したコンテンツ名で `rg` し、死んだ参照が残っていないこと。

## リスク・未決事項

- **描画パイプライン用の Rust**（`native/render`, `native/window`, `native/app` 等）を今後も維持するか。ゲーム NIF だけ削っても `mix` と `cargo` の二段構えは残る可能性がある。
- **VR / `features: ["xr"]`** を将来どうするか。NIF 撤去と XR 入力スレッドの関係を `Core.NifBridge` コメントおよび `workspace/1_backlog` の既存 VR 項目と突き合わせる。
- `SimpleBox3D` 削除により `BulletHell3D` のコメント・共通化前提が古くなるため、doc とコメントの軽い更新が必要。
- **Formula 用 NIF を残すか否か**: 残す場合は `native/nif` の「ゲーム」と「式」の境界をコード上でも明確にする。残さない場合は `Core.Formula` の Elixir 実装を先に完了させる。

## Definition of Done（本計画書の完了）

- 上記フェーズ 1〜5 のチェックがすべて満たされる。
- リポジトリ内に削除対象コンテンツのモジュール実体が残っていない（意図的なアーカイブを除く）。
- **ゲームシミュレーション用** NIF への依存がコードベースから除去されている、または「残す API がゼロ」であることが grep で確認できる。FormulaTest に必要な式実行経路は意図どおり動作している。
