# 実施計画: コンテンツ縮小（3 本維持）とゲーム系 NIF 撤去

## 前提

- **維持**: `Content.CanvasTest`, `Content.BulletHell3D`, `Content.FormulaTest`（およびそれぞれの `playing` / 付随シーン）。`FormulaTest` は Formula エンジン検証の**想定どおりの利用**を継続する。
- **削除**: `AsteroidArena`, `RollingBall`, `SimpleBox3D`, `VampireSurvivor`。
- **将来（本計画の削除対象外）**: `apps/contents/lib/contents/builtin` と `apps/contents/content_definitions` — コンテンツ爆増時の整理用。対の関係は `workspace/1_backlog/builtin-content-future.md` に記載。コード・ディレクトリは未着手でもよい。
- 本計画は **コンパイル・テスト・ローカル起動が通ること**を各フェーズの完了条件とする。

## フェーズ 0: インベントリ（着手前チェックリスト）

- [ ] `rg` / IDE で削除モジュール名・シーンモジュールの参照を一覧化（`config/`、`apps/server/`、`apps/core/lib/core/config.ex`、`Contents.Scenes.Stack`、テスト、`docs/`）。
- [ ] `builtin` について `workspace/1_backlog/builtin-content-future.md` を最新化し、将来の役割が一言で追える状態にする（アーキテクチャ overview 等へのリンク追記は任意）。
- [ ] `Core.Formula.run/3` の呼び出し元を全列挙し、**FormulaTest 維持**に伴い `run_formula_bytecode` 等の経路をどう残すか（NIF 最小化 vs Elixir 化）を方針として 1 段落で書く。
- [ ] `Contents.Events.Game` から**ゲーム ECS 系** NIF を外した後のフレーム駆動モデル（Elixir のみ tick、インジェクション経路の単純化）を 1 段落で方針化する。

## フェーズ 1: コンテンツ削除（Elixir）

- [ ] **削除対象のみ**指定ディレクトリ・トップレベル `*.ex`（各 `Content.*`）を削除（`formula_test` は対象外）。
- [ ] `apps/contents/test/content/` 以下の**削除コンテンツ専用**テストを削除またはスキップ理由をコメント（削除推奨）。
- [ ] デフォルトコンテンツを `Content.CanvasTest` / `Content.BulletHell3D` / `Content.FormulaTest` のいずれかに統一（開発用途に応じて切替可能ならコメントで明記）:
  - `apps/core/lib/core/config.ex` の `@default_content`
  - `apps/server/lib/server/application.ex` の `:current`
  - `config/config.exs` のコメント・参照
  - `config/formula_test.exs` は **FormulaTest 用として維持**（`mix` の config パスから外さない）。削除コンテンツ専用 config のみ整理する。
- [ ] `Contents.Scenes.Stack` 等のハードコードされた `Content.VampireSurvivor` を `Core.Config.current()` ベースに寄せる。
- [ ] ルート `Content` の moduledoc（`apps/contents/lib/contents.ex`）を **維持 3 コンテンツ**に更新。

## フェーズ 2: 削除コンテンツ専用コンポーネント・イベントの整理

- [ ] `Contents.Events.Game` 内の VampireSurvivor 向け分岐（例: 武器スロット注入フォールバック）を、残存コンテンツに不要なら削除。
- [ ] `Contents.Events.Game.Diagnostics` の NIF メトリクス（敵弾数・SSoT チェック等）を、NIF 撤去方針に合わせて Elixir のみまたは削除。
- [ ] `Contents.Components.Category.Spawner` が残存コンテンツで未使用なら削除、使用されていれば NIF 非依存の API に変更。
- [ ] `PhysicsEntity` 等、Asteroid / NIF 物理専用と分かるコンポーネントは参照ゼロ確認のうえ削除または doc のみ残す。

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
