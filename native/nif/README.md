# nif

Elixir 向け **Rustler NIF**。`mix compile` で release ビルドされ、`Core.NifBridge` からロードされる。

## 現行の責務（フェーズ 4 以降）

- **`run_formula_bytecode/3`** のみ — コンテンツ数式 VM（バイトコード実行）
- ゲーム ECS・物理・protobuf フレーム注入・セーブ用 NIF は **削除済み**（復旧は Git 履歴の `physics/` 等を参照）

## ソース構成

- `src/lib.rs` — `rustler::init!`（`Elixir.Core.NifBridge`）
- `src/formula/` — VM・デコード・オペコード
- `src/nif/formula_nif.rs` — NIF エントリ
- `src/nif/load.rs` — ロード時の panic フック・`env_logger` 初期化（リソース型は登録しない）

## 依存

- `rustler`, `log`, `env_logger` のみ（旧 `audio` / `render_frame_proto` / `shared` / `prost` 等は除去）

## ワークスペース

- `native/Cargo.toml` の `members` に `nif` は従来どおり含まれる
- デスクトップ `app` は **`nif` に依存しない**（既定解像度は `shared::display`）

## XR

VR 入力はクライアント `app` → `xr` → `network` 経由で Elixir へ送る。`nif` クレートに XR 専用コードはない。
