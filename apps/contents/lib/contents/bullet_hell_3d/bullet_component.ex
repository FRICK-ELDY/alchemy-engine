defmodule Content.BulletHell3D.BulletComponent do
  @moduledoc """
  弾発射タイミング管理コンポーネント。

  BulletHell3D では弾の発射ロジックは Playing シーンの tick/1 に内包されている。
  このコンポーネントは将来的に弾発射エフェクト・SE トリガーなどを追加する際の
  拡張ポイントとして存在する。

  現時点では Rust フレームイベントを受け取る口として機能し、
  弾発射に関連するイベントをシーン state に反映する役割を担う。
  """
  @behaviour Core.Component

  # 現時点では弾ロジックは Playing シーンに集約されているため、
  # コールバックは最小限の実装とする。
  # 将来的に {:bullet_fired, id} などのイベントを追加した場合はここで処理する。
end
