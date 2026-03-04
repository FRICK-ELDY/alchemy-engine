defmodule GameContent.BulletHell3D.SpawnComponent do
  @moduledoc """
  BulletHell3D のワールド初期化コンポーネント。

  Rust 物理エンジン（ECS）は使用しないが、エンジンループが常に動いているため
  `set_world_size` で最小限のワールドサイズを設定する。
  ゲームロジックは Elixir 側のシーン state で完結する。
  """
  @behaviour Core.Component

  # Rust 側の physics_step が map_size < PLAYER_SIZE でパニックしないよう
  # 十分大きな値を設定する（SimpleBox3D と同じ値）。
  @map_size 2048.0

  @impl Core.Component
  def on_ready(world_ref) do
    Core.NifBridge.set_world_size(world_ref, @map_size, @map_size)
    :ok
  end
end
