# Protobuf 移行（概要）

Zenoh 経由のペイロードを Erlang term（ETF）から **Protocol Buffers** に揃える移行の、公開向けの要約です。

## 契約（ワイヤ上の単一ソース）

ドメイン（ルール・公式状態）は **Elixir** が担う。**Protobuf で表現するメッセージ形**は **`proto/*.proto`** を単一ソースとする。UDP 外枠や JSON など **別形式**は `proto` の外（全体像は [overview.md](./overview.md#設計思想) の表）。

- スキーマ定義: リポジトリ直下の **`proto/*.proto`**
- Elixir: `apps/network/lib/network/proto/`（`use Protobuf` 手書きが多い）
- Rust: `rust/client/network` / `rust/nif` 等（`prost`；一部手書き `Message`）

## 現状（運用上）

- **フレーム・入力・injection・client_info** はワイヤ上 protobuf のみ。旧バイナリ形式のフォールバックおよび `bert_encode` 互換名は削除済み。UDP も ETF（`term_to_binary`）ではなく protobuf payload を圧縮して送る方式に統一した。残作業は作業用ツリー `workspace/2_todo/protobuf-migration-p5-serialization-followups.md` をリポジトリ内で検索（本 `docs` からは `workspace/` へリンクしない方針のためパス記載のみ）。
- レガシー ETF の map 形は [erlang-term-schema.md](./erlang-term-schema.md) に記載（参照・デバッグ用）。
- `rust/client/network` のフレーム受信は `decode_pb_render_frame` のみ。**サーバーとデスクトップクライアントは同時更新**を前提とし、片側のみ更新した構成はサポートしない（リリース運用ポリシー）。

## 開発者向け

- **生成の公式エントリ**: リポジトリルートで `mix alchemy.gen.proto`（実装は段階的に追加）。
- **完全自動化**の手順・ツール・CI: リポジトリ内 `workspace/2_todo/protobuf-full-automation-procedure.md`（本 `docs` からはリンクしない。パスはリポジトリで検索）。
- 開発ガイドの入口: [development.md](../../development.md)

## 詳細なタスク・フェーズ一覧

フェーズ分割・チェックリストなどの**細かいバックログ**は、リポジトリ内の作業用ツリー側で管理する。**本 `docs/` から `workspace/` へのリンクは張らない**方針とする。
