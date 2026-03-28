# Policy: Elixir × Zenoh — ネットワーク・フレーム配信

[← index](./index.md)

---

## 1. Zenoh メッセージハンドラ内で重い処理を行わない

**やってはいけないこと**: 入力受信・フレーム配信のコールバック内で、演算・大量のデータ変換・同期的な NIF 呼び出し（長時間ブロックしうるもの）を行うこと。

**理由**:

- Zenoh の subscribe ハンドラは Elixir プロセス上で実行される
- 重い処理が入るとメッセージキューが詰まり、60Hz のフレーム配信や入力配送が遅延する
- 多数プレイヤー時のバックプレッシャー設計と矛盾する

**やるべきこと**: ハンドラは受信・軽量なディスパッチのみ。本処理は GenServer に送信して非同期で行うか、Rust 側に委譲する。

---

## 2. フレーム直列化は protobuf のみ

**方針**: Zenoh 経由のサーバー→クライアント **RenderFrame** は `proto/render_frame.proto` に基づく **protobuf** のみ。スキーマ外のバイナリ形式で配信しない。

**理由**:

- スキーマの単一情報源と Elixir / Rust の契約整合が取りやすい
- [zenoh-frame-serialization.md](./why_adopted/zenoh-frame-serialization.md)、[protobuf-migration.md](../architecture/protobuf-migration.md) の方針に従う

**やるべきこと**: `Content.FrameEncoder` で protobuf バイナリを生成し、クライアント（Rust）は `decode_pb_render_frame` でデコードする。
