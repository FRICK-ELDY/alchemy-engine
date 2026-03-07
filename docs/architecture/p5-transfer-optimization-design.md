# P5 転送効率化 — 設計ドキュメント

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/contents-defines-rust-executes.md) P5、[contents-to-physics-bottlenecks.md](contents-to-physics-bottlenecks.md) セクション 6

---

## 1. 概要

P5 は Elixir ↔ Rust 間のデータ転送効率化を目的とする。**定義の所在**とは独立だが、定義を渡す際のオーバーヘッドを削減する。

**実装済み**: P5-1（バッチ注入 API）、P5-3（decode 最適化）、P5-4（get_render_entities ダブルバッファ）

---

## 2. P5-2: MessagePack バイナリ形式（未実装）

### 2.1 採用形式: MessagePack

バイナリ化には **MessagePack** を採用する。

| 項目     | 内容                         |
| ------ | -------------------------- |
| メリット   | 既存ライブラリ、型情報、言語間の互換性      |
| Elixir | msgpax                      |
| Rust   | rmp-serde / rmp 等             |

### 2.2 適用対象

- **push_render_frame**: DrawCommand リスト・UiCanvas・CameraParams・MeshDef を MessagePack バイナリで渡す
- **set_frame_injection**（将来）: injection_map を MessagePack 化。[set-frame-injection-messagepack-design.md](set-frame-injection-messagepack-design.md) 参照

### 2.3 実装方針

1. **エンコード**: Elixir 側（contents）で msgpax によりバイナリ化
2. **デコード**: Rust 側（render_frame_nif）で rmp-serde によりバイナリから構造体へ変換
3. **型マッピング**: DrawCommand 仕様（`docs/architecture/draw-command-spec.md`）に基づき Elixir ↔ Rust でスキーマを揃える
4. **後方互換**: タプル形式パスは残し、コンテンツごとに MessagePack パスへ段階移行

### 2.4 留意点

- msgpax の依存追加（mix.exs）
- rmp-serde / rmp の依存追加（Cargo.toml）
- スキーマ変更時は Elixir・Rust 両方の型マッピングを更新する必要あり
