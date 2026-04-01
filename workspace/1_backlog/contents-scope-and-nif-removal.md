# バックログ: コンテンツ縮小とゲーム系 NIF / Rust の整理

## 背景

Vampire Survivors 系から VRSNS までを一気に載せる方針のもと、複数コンテンツと Rust 側ゲーム（ECS・物理・NIF ブリッジ）が絡み合い、変更コストと認知負荷が高くなっている。

## 目的（ゴール）

1. **コンテンツの明示的な縮小**  
   当面は次の **3 つ**を第一級コンテンツとして維持する。
   - `apps/contents/lib/contents/canvas_test`
   - `apps/contents/lib/contents/bullet_hell_3d`
   - `apps/contents/lib/contents/formula_test`（Formula エンジン検証・想定どおりの Elixir↔Rust 経路を継続利用）

2. **削除するコンテンツ（予定）**  
   以下のモジュール・ディレクトリ・関連テスト・設定参照をリポジトリから取り除く。
   - `asteroid_arena`
   - `rolling_ball`
   - `simple_box_3d`
   - `vampire_survivor`

3. **将来: `builtin` コンテンツ（削除対象外・ドキュメントで残す）**  
   `apps/contents/lib/contents/builtin` は**コンテンツが増えた将来の整理用**に必要となる構成と位置づける。`apps/contents/content_definitions` と対で設計する前提（詳細は **`workspace/1_backlog/builtin-content-future.md`**）。現時点でこれらのディレクトリが未配置でもよい。  
   **方針**: 本縮小・NIF 整理のスコープからは外し、実装は後続タスクとする。意図は上記メモおよび必要に応じて `docs/` のアーキテクチャ記述に残し、消えないようにする。

4. **ゲーム関連 NIF / Rust の縮退**  
   上記縮小に合わせ、**ゲームループ・ワールド・物理・敵弾など Rust ECS 前提の NIF** に依存する経路をなくし、残存コンテンツ（Canvas / 弾幕 3D / Formula 検証）が動作するアーキテクチャに寄せる。  
   **FormulaTest** は `Core.Formula` → `NifBridge.run_formula_bytecode` 等の**式実行経路を想定どおり使う**ため、ゲーム ECS 用 API の削除と混同しないこと（式用 NIF は維持するか、事前に純 Elixir 実装へ移してから NIF を削るかを計画で決める）。  
   ※クライアント描画・ウィンドウ・`render_frame` 等、**「ゲームシミュレーション」と切り分けられる Rust** は本項のスコープ外とするか、別ドキュメントで継続／廃止を判断する（本バックログでは「ゲーム系 NIF を廃止する」ことを主目的とする）。

## 受け入れ条件（バックログ完了＝2_todo に降ろせる状態）

- 維持する **3 コンテンツ**、削除リスト、**将来 `builtin` をドキュメントで残す方針**が文書上固定されている。
- `Core.NifBridge` / `Contents.Events.Game` / `Core.SaveManager` / `Core.Formula` など、NIF に触れる主要モジュールの**依存関係マップ**が 1 枚（箇条書きで可）用意されている。**ゲーム用 API** と **Formula 用 API** が区別されていること。
- NIF 完全撤去と「描画用 Rust のみ残す」のどちらを最終形にするか、プロダクト判断が書かれている（未決なら「要決定」として 2_todo のリスクに載せる）。Formula 用 NIF を残す場合は、その範囲が明示されていること。

## 非目標（このバックログではやらない）

- VRSNS 機能そのものの新規実装。
- ドキュメント全体の全面改訳（必要最小限の README / config コメント更新は 2_todo 側で扱う）。

## 関連ドキュメント

- `workspace/1_backlog/builtin-content-future.md` — `contents/builtin` の将来方針（本バックログとセットで参照）

## 関連コード（調査の起点）

- `apps/contents/lib/events/game.ex` — ワールド生成・Rust ゲームループ・インジェクション
- `apps/core/lib/core/nif_bridge.ex` — Rustler / `native/nif`
- `apps/core/lib/core/formula.ex` — 式実行と NIF（FormulaTest の想定経路）
- `apps/core/lib/core/save_manager.ex` — セーブと NIF の連携
- `apps/contents/lib/components/category/spawner.ex` — NIF へのワールド／エンティティ注入
- `native/Cargo.toml` ワークスペースメンバー（`nif` クレートの位置づけ）
