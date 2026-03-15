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

- `nif`（一部定数参照）
- `shared`
