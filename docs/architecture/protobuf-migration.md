# Protobuf 移行（概要）

Zenoh 経由のペイロードを Erlang term（ETF）から **Protocol Buffers** に揃える移行の、公開向けの要約です。

## 契約（単一ソース）

- スキーマ定義: リポジトリ直下の **`proto/*.proto`**
- Elixir: `apps/network/lib/network/proto/`（`use Protobuf` 手書きが多い）
- Rust: `native/network` / `native/nif` 等（`prost`；一部手書き `Message`）

## 現状（運用上）

- **フレーム・入力・injection** はワイヤ上 protobuf のみ。`client_info` は protobuf 主経路で、失敗時のみ MessagePack へフォールバックする。UDP の `term_to_binary` や MessagePack / `bert_encode` 名の整理などのフォローアップは、作業用ツリー `workspace/2_todo/protobuf-migration-p5-serialization-followups.md` をリポジトリ内で検索（本 `docs` からは `workspace/` へリンクしない方針のためパス記載のみ）。
- レガシー ETF の map 形は [erlang-term-schema.md](./erlang-term-schema.md) に記載（参照・デバッグ用）。

## 開発者向け

- **生成の公式エントリ**: リポジトリルートで `mix alchemy.gen_proto`（実装は段階的に追加）。
- **完全自動化**の手順・ツール・CI: リポジトリ内 `workspace/2_todo/protobuf-full-automation-procedure.md`（本 `docs` からはリンクしない。パスはリポジトリで検索）。
- 開発ガイドの入口: [development.md](../../development.md)

## 詳細なタスク・フェーズ一覧

フェーズ分割・チェックリストなどの**細かいバックログ**は、リポジトリ内の作業用ツリー側で管理する。**本 `docs/` から `workspace/` へのリンクは張らない**方針とする。
