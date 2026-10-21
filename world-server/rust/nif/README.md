# nif

Elixir 向け **Rustler NIF**。`mix compile` で release ビルドされ、`Core.NifBridge` からロードされる。

## 現行の責務（フェーズ 4 以降）

- **`run_formula_bytecode/3`** のみ — コンテンツ数式 VM（バイトコード実行）
- ゲーム ECS・物理・protobuf フレーム注入・セーブ用 NIF は **削除済み**（復旧は Git 履歴の `physics/` 等を参照）

## 方針: Formula は Rust、境界はコードで分ける

サーバ側 Elixir はオーケストレーションと状態管理を担い、**数値・バイトコード VM の実行は本クレート（Rust NIF）に任せる**方針とする。

**「ゲーム」と「式」の境界**（過去に同一クレートに同居していたときの整理用語）は、現状では次のようにコード上で表現されている。

| 側 | 役割 |
|:---|:---|
| **ゲームシミュレーション** | Elixir（`contents` のシーン・コンポーネント）およびクライアント描画パイプライン。`rust/nif` には **含めない**。 |
| **式（Formula）** | `src/formula/` の VM と `src/nif/formula_nif.rs` の NIF エントリのみ。他用途の Rust をここに混在させない。 |

**Elixir からの呼び出し**は **`Core.Formula.run/3` 等**（`apps/core/lib/core/formula.ex`）を正とし、アプリ・コンテンツから **`Core.NifBridge.run_formula_bytecode` を直接呼ばない**。NIF は Rustler のロード先として `Core.NifBridge` に載るが、公開 API の境界は `Core.Formula` に置く。

**Cargo 依存**も式実行に必要な最小限にし、描画・ゲーム用クレートを `nif` に引き込まない（境界を依存グラフでも維持する）。

## ソース構成

- `src/lib.rs` — `rustler::init!`（`Elixir.Core.NifBridge`）
- `src/formula/` — VM・デコード・オペコード
- `src/nif/formula_nif.rs` — NIF エントリ
- `src/nif/load.rs` — ロード時の panic フック・`env_logger` 初期化（リソース型は登録しない）

## 依存

- `rustler`, `log`, `env_logger` のみ（旧 `audio` / `render_frame_proto` / `shared` / `prost` 等は除去）

## ワークスペース

- `rust/Cargo.toml` の `members` に `nif` が含まれる
- デスクトップ `app` は **`nif` に依存しない**（既定解像度は `shared::display`）

## XR

VR 入力はクライアント `app` → `xr` → `network` 経由で Elixir へ送る。`nif` クレートに XR 専用コードはない。
