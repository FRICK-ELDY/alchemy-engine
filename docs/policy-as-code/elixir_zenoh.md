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

## 2. フレーム直列化は Erlang term を用いる

**やってはいけないこと**: Zenoh 経由のサーバー→クライアント RenderFrame 配信に MessagePack を用いること。

**理由**:

- `term_to_binary` は C 実装の BIF で最も高速
- 60Hz フルフレームのエンコード負荷を抑えたい
- 本プロジェクトの採用方針に反する（[zenoh-frame-serialization.md](./why_adopted/zenoh-frame-serialization.md)）

**やるべきこと**: `:erlang.term_to_binary(frame_term, [:compressed])` を用い、クライアント側では `bert` 等でデコードする。
