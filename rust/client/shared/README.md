# shared

Elixir との契約・型・補間・予測を提供する基底クレート。**依存なし**。

## 責務（The Mirror - 鏡）

- **Zero-Copy**: `bytemuck` による `#[repr(C)]` 構造体で、Elixir-Rust 間のバイナリをパースせず直接参照
- **Smoothing**: サーバーの低頻度更新（20Hz）を 60Hz 描画用に線形補間
- **Predict**: 入力予測によるレイテンシ対策

## 主要モジュール

- `display` — 既定ウィンドウ解像度（`SCREEN_WIDTH` / `SCREEN_HEIGHT`、デスクトップ `app` 用）
- `types` — Elixir との共通規格となる `#[repr(C)]` 構造体
- `store` — スナップショット保持（過去と現在）
- `interp` — 線形補間（Lerp）ロジック
- `predict` — 入力予測ロジック

## 設計指針

**Shared types first**: 契約変更時は必ず `types.rs` から修正し、サーバーとクライアントの双方を更新する。
