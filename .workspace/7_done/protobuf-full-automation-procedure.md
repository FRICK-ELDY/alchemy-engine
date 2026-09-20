# Protobuf 完全自動化 — 実施手順書

> **状態**: 作業中（生成パイプラインの本実装・手書きコードの廃止は未完了。ワイヤ上の protobuf 移行完了とは別タスク）。  
> 目的: `proto/*.proto` を**唯一の契約**とし、Rust（`prost`）と Elixir（`protobuf`）のコードを **生成物で揃える**。手書き `Message` / 手書き `use Protobuf` を廃止する。  
> 対象読者: 本リポジトリでスキーマと生成パイプラインを触る開発者。  
> 公開向けの短い概要: [docs/architecture/protobuf-migration.md](../../docs/architecture/protobuf-migration.md)

---

## 1. ゴールと前提

### 1.1 ゴール

| 言語 | 現状（移行前） | ゴール |
|:---|:---|:---|
| Rust | `protobuf_codec.rs` 等に手書き `prost::Message` | `prost-build` + `build.rs` で `.proto` から生成 |
| Elixir | `render_frame_native.ex` 等に手書き DSL | `protoc` + `protoc-gen-elixir` で `.ex` を生成 |
| 契約 | `proto/*.proto` と二重管理 | **`proto/*.proto` のみ**を編集し、**`mix alchemy.gen.proto`** で生成物を更新する |

### 1.2 前提ツール

| ツール | 用途 |
|:---|:---|
| [`protoc`](https://grpc.io/docs/protoc-installation/) | `.proto` → Elixir / 検証。CI とローカルの両方に入れる |
| Rust `stable` | `prost-build` / `cargo build` |
| Elixir 1.19+ | `mix`、および下記プラグイン |
| `protoc-gen-elixir` | Elixir 用コード生成（下記インストール） |

環境変数 `PROTOC` に `protoc` 実行ファイルのフルパスを指定すると、PATH に依存しない（Windows 向け）。

### 1.3 Elixir プラグイン `protoc-gen-elixir` の導入

[elixir-protobuf/protobuf](https://github.com/elixir-protobuf/protobuf) の手順に従う。代表的な方法:

```bash
mix escript.install hex protobuf
```

生成時、`protoc` が `PATH` 上で `protoc-gen-elixir` を見つけられるようにする（`~/.mix/escripts` を PATH に追加する等）。

バージョンは `mix.exs` の `{:protobuf, "~> 0.16"}` と **互換があるリリース**を選ぶ（プラグインとランタイムの組み合わせはリリースノートを確認）。

---

## 2. `.proto` 側の整備（自動化の前提）

### 2.1 パッケージ名と Elixir モジュール接頭辞

生成コードのモジュール名は **package** と **オプション**で決まる。既存の `Network.Proto.*` と揃えるには、各ファイルで例えば次を検討する（要: 実際の `protoc-gen-elixir` のバージョンに合わせて調整）。

```protobuf
syntax = "proto3";

package alchemy.render;

// protoc-gen-elixir がサポートする場合のみ（未サポートなら生成コマンドのフラグで代替）
// option elixir_module_prefix = "Network.Proto";
```

- 接頭辞を `.proto` で付けられない場合は、`protoc` 実行時の **`--elixir_opt=...`** や生成後のラッパで吸収する（チームで一つの方針に固定する）。

### 2.2 依存関係の import

`proto/` 内で `import` する場合、`protoc` の `--proto_path` を **リポジトリの `proto/`** に統一し、`prost-build` の `include` も同じにする。

### 2.3 単一の生成エントリ（必須）

**リポジトリルートで `mix alchemy.gen.proto`** を唯一のエントリとする（`apps/core/lib/mix/tasks/alchemy.gen.proto.ex`）。

- Elixir の `protoc` 呼び出しと、Rust 側で `prost-build` を走らせる `cargo build` のトリガーを **このタスク内**にまとめる。
- OS 差のある **`scripts/gen_proto.sh` / `.ps1` は置かない**（PATH・改行コードのばらつきで事故りやすいため）。

実装は段階的に本タスクへ追加する。完了までは手順 §3・§4 を手動で実行してもよい。

---

## 3. Rust: `prost-build` 導入

### 3.1 対象クレート

- まず **`native/network`** に限定して導入し、手書きを置き換えてから **`native/nif`** へ展開するのが安全。
- **同一 `.proto` を複数クレートで生成しない**ようにする（推奨: **`native/proto_generated`** のような共通クレートを1つ作り、`network` / `nif` はそれに依存）。

### 3.2 `Cargo.toml`（例: `native/network`）

```toml
[dependencies]
prost = "0.14"

[build-dependencies]
prost-build = "0.14"
```

バージョンはプロジェクトのロックファイルと揃える。

### 3.3 `build.rs`（クレート直下・概念例）

```rust
use std::path::Path;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_dir = Path::new("../../proto");
    let protos = &[
        proto_dir.join("render_frame.proto"),
        // 必要に応じて追加
    ];
    let includes = &[proto_dir];
    prost_build::compile_protos(protos, includes)?;
    Ok(())
}
```

- パスはクレートからの相対位置に合わせて修正する。
- 生成ファイル名は **package 名**に依存する。初回は `cargo build` 後に `OUT_DIR`（`target/.../build/.../out`）を開き、実際の `include!(...)` 名を確認する。

### 3.4 `src/lib.rs` での取り込み

```rust
pub mod pb {
    include!(concat!(env!("OUT_DIR"), "/alchemy.render.rs"));
}
```

パッケージ `alchemy.render` の場合、ファイル名は環境により `alchemy.render.rs` 等になる。**必ずビルド成果物で確認**する。

### 3.5 既存コードの置き換え

1. 生成モジュールを `include` し、既存の手書き型と **並行**でコンパイルできる状態にする。
2. `protobuf_render_frame.rs` 等の **変換レイヤ**だけを、生成型を参照するよう差し替える。
3. 手書き `struct XxxPb` を削除する。

### 3.6 CI

`cargo build` が **`protoc` なしで失敗しない**よう、CI ジョブに `protoc` のインストール（例: `arduino/setup-protoc`、公式バイナリ、`choco install protoc` 等）を追加する。

---

## 4. Elixir: `protoc-gen-elixir` による生成

### 4.1 出力先の方針

| 方針 | メリット | 注意 |
|:---|:---|:---|
| **生成専用ディレクトリ**（例: `apps/network/lib/network/proto/generated/`）に出し、Git にコミットする | レビューで差分が見える | `.formatter.exs` の対象外や `mix format` の運用を決める |
| 生成物を Gitignore し、CI で毎回生成 | リポジトリが薄い | ローカルと CI で同じ `protoc` バージョンが必須 |

チームでどちらかを決める。

### 4.2 生成コマンド（概念例）

リポジトリルートから（パスは環境に合わせて調整）:

```bash
protoc \
  --elixir_out=apps/network/lib/network/proto/generated \
  --proto_path=proto \
  proto/render_frame.proto \
  proto/input_events.proto \
  proto/frame_injection.proto \
  proto/client_info.proto
```

- `--elixir_opt` で `package_prefix` や `include_docs` 等が必要なら、[プラグインの README](https://github.com/elixir-protobuf/protobuf) に従う。
- `oneof` / `proto3_optional` は **生成されたモジュール**が `protobuf` 0.16 の期待と一致するか、初回に差分を確認する。

### 4.3 アプリケーションコードの接続

1. 生成モジュールを `mix compile` に含める（`mix.exs` の `elixirc_paths` に `generated` を含める等）。
2. 既存の `Network.Proto.RenderFrame` 等の **手書きファイルを削除**し、`alias` または `import` で生成モジュールを参照する。
3. モジュール名が変わる場合は、呼び出し側（`Content.FrameEncoder` 等）を一括置換する。

### 4.4 手書き DSL を残す場合

完全自動化の対象外にするファイルは、**`.proto` に存在しない拡張**に限定する（例: アプリ固有のヘルパのみ）。ワイヤ型は生成に寄せる。

---

## 5. `native/nif` との共有

- **推奨**: `native/proto_generated`（仮称）クレートを1つ作り、`prost-build` はそこだけで実行。`network` と `nif` は `proto_generated` に依存。
- **代替**: `nif` にも `build.rs` を置くが、**二重生成**で定義が食い違うリスクがあるため非推奨。

---

## 6. 検証チェックリスト

- [x] `proto/` のみを編集し、`cargo build` / `mix compile` が通る。
- [x] 手書き `prost` 構造体が該当メッセージから消えている。
- [x] 手書き `use Protobuf` の該当メッセージが消えている。
- [x] Zenoh / NIF の結合テストまたは手動で、フレーム・入力・injection が従来どおり動く。
- [x] CI で `protoc` が利用可能。
- [x] `development.md` には手順を書かず、**本書と `docs/architecture/protobuf-migration.md` に集約**する。
- [x] **`mix alchemy.gen.proto`** が Elixir / Rust の生成をまとめて実行する（または明確にサブステップを表示する）。

---

## 7. ワンショット生成（公式エントリ）

リポジトリルートで次を実行する。

```bash
mix alchemy.gen.proto
```

この Mix タスクが次を担う（実装は本タスクに順次追加する）。

1. `protoc` + `protoc-gen-elixir` … Elixir 出力（出力先・オプションは実装時に固定）
2. `cargo build -p <生成クレート>` … `prost-build` による Rust 生成のトリガー

**シェルスクリプト（`scripts/gen_proto.sh` 等）は採用しない。** Mix と `System.cmd/Port` で OS をまたいで同一手順にする。

---

## 8. 参照

- [protobuf-migration-plan.md](../7_done/protobuf-migration-plan.md) — 移行フェーズ・バックログ（主経路の移行は完了）
- [docs/architecture/protobuf-migration.md](../../docs/architecture/protobuf-migration.md) — 公開向け概要
- [development.md](../../development.md) — 開発ガイド（生成エントリは `mix alchemy.gen.proto`）
