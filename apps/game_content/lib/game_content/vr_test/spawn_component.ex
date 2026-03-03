defmodule GameContent.VRTest.SpawnComponent do
  @moduledoc """
  VRTest のワールド初期化コンポーネント。

  Rust 物理エンジンは使用しないが、エンジンループとの整合のため
  最小限のワールドサイズ設定を行う。
  """
  @behaviour GameEngine.Component

  @map_size 2048.0

  @impl GameEngine.Component
  def on_ready(world_ref) do
    GameEngine.NifBridge.set_world_size(world_ref, @map_size, @map_size)
    :ok
  end
end
