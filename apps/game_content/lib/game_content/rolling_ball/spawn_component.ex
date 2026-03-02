defmodule GameContent.RollingBall.SpawnComponent do
  @moduledoc """
  RollingBall のワールド初期化コンポーネント。

  Rust 物理エンジン（ECS）は使用しない。
  エンジンループが要求するワールドサイズのみ設定する。
  """
  @behaviour GameEngine.Component

  # SimpleBox3D と同様に Rust 側の PLAYER_SIZE 定数（64.0px）を超える値を設定する。
  @map_size 2048.0

  @impl GameEngine.Component
  def on_ready(world_ref) do
    GameEngine.NifBridge.set_world_size(world_ref, @map_size, @map_size)
    :ok
  end
end
