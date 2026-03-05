# Rust: input_openxr — OpenXR 入力ブリッジ

## 概要

`input_openxr` クレートは **OpenXR** を用いた VR 入力ブリッジです。VR ヘッドセット・コントローラー・トラッカーなどの入力を受け取り、ゲームエンジン側に渡す役割を担います。

- **パス**: `native/input_openxr/`
- **依存**: `log = "0.4"`, `openxr = "0.21"`（optional, `openxr` feature）

## 機能

- **openxr** feature を有効にすると、OpenXR ランタイム経由で VR デバイスの入力（ポーズ・ボタン・トリガー等）を取得可能。
- デスクトップのキーボード・マウスは [render](./render.md) 周辺の `input` クレート（winit）が担当。VR 入力は本クレートで別途扱う設計。

## 関連ドキュメント

- [アーキテクチャ概要](../overview.md)
- [render](./render.md)（デスクトップ入力・winit）
