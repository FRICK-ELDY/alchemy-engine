# render

wgpu を用いた共通レンダラー。プラットフォームを問わず同一の描画結果を保証。

## 責務（The Eye - 瞳）

- GPU 描画パイプライン、シェーダー（WGSL）管理
- **Instancing**: Elixir から届く大量オブジェクトを GPU インスタンシングで一括描画
- egui HUD 描画
- ヘッドレスモード（ウィンドウは `window` が生成）

## 構成

- `common` — 共通パイプライン、シェーダー管理
- `platform/` — target_os による Surface 生成（desktop / web）

## 依存

- `shared`（`RenderFrame` 契約型・背景クリア色など）
- `render_frame_proto` — `proto/render_frame.proto` のデコード（`decode_pb_render_frame`）。NIF は `render` ではなくこのクレートのみを引く
