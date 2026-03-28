# P5 転送効率化 — 設計ドキュメント

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) P5、[contents-to-physics-bottlenecks.md](contents-to-physics-bottlenecks.md) セクション 6

---

## 1. 概要

P5 は Elixir ↔ Rust 間のデータ転送効率化を目的とする。**定義の所在**とは独立だが、定義を渡す際のオーバーヘッドを削減する。

**実装済み**: P5-1（バッチ注入 API）、P5-2（フレームの Protobuf）、P5-3（decode 最適化）、P5-4（get_render_entities ダブルバッファ）

---

## 2. P5-2: フレームの Protobuf バイナリ形式

### 2.1 採用形式

バイナリ化には **Protobuf** を採用する。

| 項目   | 内容 |
| ------ | ---- |
| スキーマ | `proto/render_frame.proto`（SSoT） |
| Elixir | `Content.FrameEncoder` → `Alchemy.Render.RenderFrame.encode/1` |
| Rust   | `render_frame_proto::decode_pb_render_frame`（`prost`） |

### 2.2 適用対象

- **Zenoh フレーム配信**: `FrameBroadcaster.put` → `Network.ZenohBridge.publish_frame` のペイロード
- **NIF 契約検証**: `push_render_frame_binary`（デコード成功で `:ok`。NIF 層は描画を持たない）

### 2.3 実装方針

1. **エンコード**: Elixir 側（contents）で protobuf にシリアライズ
2. **デコード**: Rust 側（`native/render_frame_proto`）で `decode_pb_render_frame`
3. **型マッピング**: [draw-command-spec.md](draw-command-spec.md) と `.proto` のフィールド番号を整合させる

### 2.4 関連

- [draw-command-spec.md](draw-command-spec.md)
- [protobuf-migration.md](protobuf-migration.md)
- [workspace/7_done/p5-transfer-protobuf-implementation-plan.md](../../workspace/7_done/p5-transfer-protobuf-implementation-plan.md)
