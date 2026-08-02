defmodule Contents do
  @moduledoc """
  コンテンツ一覧／インフラ（OTP app `:contents`）のルート。

  - `Content.*` — 個別コンテンツ実装（例: `Content.BulletHell3D`）
  - `Contents.*` — 一覧・共有インフラ（例: `Contents.Events.Game`, `Contents.FrameEncoder`）

  利用可能なコンテンツ（第一級・維持）:
  - `Content.CanvasTest`   — Canvas / ワールド空間 UI デバッグ
  - `Content.BulletHell3D` — 3D 弾幕避け
  - `Content.FormulaTest`  — Formula / Nodes 検証
  - `Content.Tetris`       — Tetris (title / play / game over)
  """
end
