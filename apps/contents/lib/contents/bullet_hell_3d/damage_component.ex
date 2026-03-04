defmodule Content.BulletHell3D.DamageComponent do
  @moduledoc """
  HP 管理・ゲームオーバー判定コンポーネント。

  BulletHell3D では HP 管理と衝突判定は Playing シーンの tick/1 に内包されている。
  このコンポーネントは将来的にダメージフラッシュ・SE トリガー・
  スコア集計などを追加する際の拡張ポイントとして存在する。

  現時点では HP 変化に関連するイベントを受け取る口として機能する。
  """
  @behaviour Core.Component

  # 現時点では HP ロジックは Playing シーンに集約されているため、
  # コールバックは最小限の実装とする。
  # 将来的に {:player_damaged, hp} などのイベントを追加した場合はここで処理する。
end
