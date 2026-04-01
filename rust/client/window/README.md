# window

winit を用いたイベントループ・窓層。OS の窓とライフサイクルを管理。

## 責務（The Shell - 殻）

- winit イベントループ、窓生成
- キーボード・マウス入力の取得
- **Normalization**: OS ごとに異なるマウス座標や DPI スケールをエンジン共通の数値に変換

## 構成

- `common` — 入力イベントの正規化
- `platform/` — OS 固有処理（Suspend/Resume 等）

## 依存

- `render`
