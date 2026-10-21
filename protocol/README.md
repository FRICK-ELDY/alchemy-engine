# Alchemy Protocol

[FRICK-ELDY](https://github.com/FRICK-ELDY) 管理の **ワイヤ契約**（主に **Protobuf `.proto`**）の単一ソースです。ゲームルールや公式状態のドメイン SSoT は [alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine) 側の Elixir にあります（二層の整理）。

## 含まれるもの

- `proto/` — Zenoh 等で共有するメッセージ定義（`alchemy.render` / `alchemy.input` 等）
- `docs/wire-overview.md` — 経路・ペイロードの要約とエンジン側詳細ドキュメントへのリンク

## バージョン方針

- 本リポジトリのみ **`vMAJOR.MINOR.PATCH`** 形式の Git タグでバージョンを打ちます（alchemy-engine のリリース番号とは独立）。
- **破壊的変更**（フィールド削除・型変更・番号の再利用など）は `MAJOR` を上げ、`CHANGELOG.md` に必ず記載してください。
- **同一 MAJOR 内**の既定の後方互換変更は、proto3 における **フィールド追加のみ** とします。`reserved` の運用は `CONTRIBUTING.md` を参照してください。

## alchemy-engine からの取り込み

エンジン側では **タグまたはコミット SHA で rev を固定**し、意図しない追従を防いでください。

### 方式 A: Git submodule（例）

ディレクトリ名は任意ですが、[alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine) では **`3rdparty/alchemy-protocol`** を既定としています。

```bash
git submodule add https://github.com/FRICK-ELDY/alchemy-protocol.git 3rdparty/alchemy-protocol
# .proto の実体: 3rdparty/alchemy-protocol/proto/
```

この場合の **`PROTO_ROOT`**（環境変数またはビルド設定）はリポジトリルートからの **`3rdparty/alchemy-protocol/proto`** です。

### 方式 B: Mix の git 依存 + sparse（例）

ルート `mix.exs` の `deps` に次のような依存を追加します（依存キー名はプロジェクトで衝突しないものに変更してください）。

```elixir
{:alchemy_protocol_files,
  git: "https://github.com/FRICK-ELDY/alchemy-protocol.git",
  sparse: "proto",
  ref: "v0.1.0",
  compile: false,
  app: false}
```

`sparse: "proto"` のとき、Mix が展開するディレクトリの **ルートがすでに `.proto` ファイル群の親**になります（例: `deps/alchemy_protocol_files/render_frame.proto`）。`mix alchemy.gen.proto`（実装: `Mix.Tasks.Alchemy.Gen.Proto`）では、このパスを **`PROTO_ROOT` としてそのまま**使い、末尾に **`/proto` を二重に付けない**でください。

### Rust（`prost-build`）

`build.rs` では **`PROTO_ROOT` 環境変数を最優先**し、未設定時のみ `CARGO_MANIFEST_DIR` からの相対パスにフォールバックする実装を推奨します（クレートの深さが異なるため、相対パスのみのハードコードは事故りやすいです）。

## プロトを上げる PR の方針（alchemy-engine）

「本リポの `vX` に追従する」変更は、**Elixir の生成物（`mix alchemy.gen.proto`）と Rust の生成・契約テスト**を **同一 PR** で更新する運用を推奨します。

## ローカル検証

```bash
protoc -I proto --include_imports --descriptor_set_out=/tmp/alchemy-descriptor.pb \
  proto/render_frame.proto proto/input_events.proto proto/frame_injection.proto proto/client_info.proto
```

Windows の場合は `--descriptor_set_out=%TEMP%\alchemy-descriptor.pb` などに置き換えてください。

## ライセンス

[Eclipse Public License 2.0](LICENSE)（alchemy-engine と同一）。
