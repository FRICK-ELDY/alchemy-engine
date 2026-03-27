# protobuf 移行 — フェーズ P5 以降の直列化まわりフォローアップ

> 作成日: 2026-03-27  
> 親計画（完了）: [protobuf-migration-plan.md](../7_done/protobuf-migration-plan.md)  
> コード生成の完全自動化（未完了）: [protobuf-full-automation-procedure.md](./protobuf-full-automation-procedure.md)

## 1. 位置づけ

Zenoh の **フレーム・movement/action・frame injection** は protobuf のみに統一済み。本ドキュメントは、当時「主経路の対象外」とした **残りの直列化経路** を整理・廃止するための **別タスク** である。

対象外だったものの内訳:

| 項目 | 現状 | 本タスクでの扱い |
|:---|:---|:---|
| `client_info`（Zenoh） | protobuf 失敗時に **MessagePack**（Msgpax）へフォールバック | フォールバック削除または互換期間の明示 |
| `native/network/src/bert_encode.rs` | 実体は `protobuf_codec` への委譲だが **互換名 `bert_encode::*` が残存** | リネームまたは呼び出し元の直接委譲へ寄せる |
| NIF `decode/msgpack_injection.rs` | レガシー。**未使用**（`mod` のみ） | 削除または用途の完全廃止宣言 |
| UDP `Protocol.compress_events` / 展開 | `term_to_binary` + zlib（**Zenoh 主経路ではない**） | プロトコル版上げとセットで ETF 廃止を検討 |

## 2. ゴール

1. **client_info**: クライアント・サーバー双方が protobuf のみで運用できる状態にし、MessagePack フォールバックを削除する（または「レガシークライアントのみ」として期限付きで残すなら、その旨をコードとドキュメントに固定する）。
2. **Rust 命名**: `bert_encode` という誤解を招くモジュール名をやめ、`protobuf_codec`（または同等）に寄せて保守コストを下げる。
3. **NIF MessagePack injection**: 利用箇所がなければモジュールごと削除し、`decode/mod.rs` を簡素化する。
4. **UDP イベント圧縮**: 方針を決める（現状維持 / protobuf 化 / 別バイナリ形式）。変更する場合は **クライアント・サーバー両方** の互換とバージョン番号を定義する。
5. **E2E 契約保証**: `Content.FrameEncoder`（Elixir）→ Rust `decode_pb_render_frame` の代表フレーム一致テスト（golden 1 本以上）を追加し、回 regressions を検出できる状態にする。

## 3. 非ゴール

- Zenoh フレーム配信の再設計（既に protobuf 確定）。
- ゲームプレイ仕様の変更。

## 4. 実施手順（推奨順）

### 4.1 棚卸し

- [x] `Msgpax` / `client_info` フォールバック: `apps/network/lib/network/zenoh_bridge.ex` の `decode_client_info/1` と、Rust 側 `protobuf_codec::encode_client_info` の送受信経路を追う。
- [x] `bert_encode` の参照: `rg "bert_encode" native/` と `network_render_bridge` 等。
- [x] `msgpack_injection`: `native/nif` 内の `apply_injection_from_msgpack` 呼び出し有無を `rg` で確認。
- [x] UDP: `apps/network/lib/network/udp/protocol.ex` の `compress_events` / `decompress_events` と利用箇所を列挙。
- [x] リリース運用: 「サーバーとデスクトップクライアントは同時更新（片側更新は非サポート）」を運用手順・リリースノートへ明記する対象ドキュメントを確定。
  - 反映先: `docs/architecture/protobuf-migration.md`, `development.md`

### 4.2 client_info を protobuf のみに（フォールバック削除）

1. デスクトップ / 接続クライアントが **常に** `protobuf_codec::encode_client_info` 相当のバイナリを送っていることを確認（既に `network_render_bridge` は protobuf 送信）。
2. サーバー側 `decode_client_info` から `Msgpax.unpack/1` 分岐を削除し、protobuf 失敗時はログ＋破棄（または明示的なエラー）に統一。
3. `mix` / アプリ依存から `Msgpax` が不要になるか確認し、不要なら `mix.exs` から外す（他用途があれば残す）。
4. 契約テスト: `Network.Proto.ClientInfo` の encode/decode に加え、**実バイト列**が Zenoh 経路で受理されることを確認（既存の `protobuf_contract_test` を拡張可）。

### 4.3 `bert_encode` 互換名の整理

1. [x] `native/network/src/bert_encode.rs` の呼び出し元をすべて `protobuf_codec::*` に差し替えるか、`bert_encode` を `protobuf_codec` の thin re-export に改名する（クレート公開 API の破壊的変更になるためリリース方針と合わせる）。
2. [x] `native/network/src/lib.rs` の `pub mod bert_encode` を削除または非推奨コメント付きで残す。
3. [x] `cargo check -p network` とデスクトップクライアントのビルドで確認。

### 4.4 NIF `msgpack_injection` の削除

1. [x] 呼び出しゼロを再確認したうえで `msgpack_injection.rs` と `decode/mod.rs` の `mod` を削除。
2. [x] `rmp-serde` が nif で他に使われていなければ `Cargo.toml` から除去。
3. [x] `mix compile` と NIF ロード確認。

### 4.5 UDP `term_to_binary` 経路（任意・別リリース単位）

1. 互換性: 既存 UDP クライアントがいるかどうかで「同時切替」か「バージョン付きパケット」かを決める。
2. [x] 代替案: イベント配列を protobuf の `repeated` で表すスキーマを `proto/` に追加する、または CBOR/JSON など別形式。
   - 本ブランチでは `RenderFrame` protobuf バイナリを UDP `:frame` payload として直送する方針に統一。
3. [x] 実装後、`network_udp_test` 等を更新。

### 4.6 フレーム E2E テスト（Elixir→Rust）

1. [x] `Content.FrameEncoder.encode_frame/5` で代表フレームを生成する fixture（commands/camera/ui/mesh）を作る。
   - `native/network/tests/fixtures/render_frame_elixir_golden.bin`
2. [x] Rust 側 `decode_pb_render_frame` で同バイナリを decode し、代表値を比較するテストを追加（最初は 1 ケースの golden で可）。
   - `native/network/tests/render_frame_e2e_contract.rs`
3. [x] スキーマ更新時の更新手順（fixture の再生成方法）をテストコメントに明記する。

## 5. 完了条件

- [x] Zenoh `client_info` に MessagePack フォールバックがない（または期限付きレガシーとして文書化済み）。
- [x] `bert_encode` 名の整理が完了し、新規開発者が ETF を連想しない。
- [x] NIF の未使用 MessagePack デコードが削除されているか、意図的に残す理由が README / mod コメントに書かれている。
- [x] UDP を触る場合は、テストと互換ポリシーが更新されている。
- [x] Elixir `FrameEncoder` と Rust `decode_pb_render_frame` の E2E 契約テスト（golden 含む）が CI で実行される。

## 6. リスク

- **client_info**: 古いクライアントだけ MessagePack を送っている場合、フォールバック削除で接続情報が ETS に入らなくなる。
- **UDP**: バイナリ形式変更は既存プレイヤーとの不一致を起こしやすい。

## 7. 参照コード（調査起点）

- `apps/network/lib/network/zenoh_bridge.ex` — `decode_client_info/1`
- `native/network/src/protobuf_codec.rs` — `encode_client_info`
- `native/network/src/protobuf_render_frame.rs` — `decode_pb_render_frame`
- `native/network/src/network_render_bridge.rs` — `publish_client_info`
- `native/nif/src/nif/decode/mod.rs` — `msgpack_injection`
- `apps/network/lib/network/udp/protocol.ex` — `compress_frame_payload` / `decompress_frame_payload`
