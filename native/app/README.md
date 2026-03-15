# app

クライアント統合層。VRAlchemy exe のエントリポイント。

## 責務

- `window` / `render` / `network` / `xr` / `audio` を統合
- Zenoh 経由で Elixir サーバーから RenderFrame を受信し描画
- キーボード・マウス・VR 入力を受け取り、network 経由で Elixir へ送信

## 構成

- `main.rs` — Desktop 用（exe）
- `lib.rs` — WASM / Mobile 向け（将来実装）

## 依存

- `network`
- `render`
- `window`
- `xr`
- `nif`（一部）
- `audio`
