defmodule GameContent.VRTest.SpawnComponent do
  @moduledoc """
  VRTest のワールド初期化コンポーネント。

  Rust 物理エンジンは使用しないが、エンジンループとの整合のため
  最小限のワールドサイズ設定を行う。
  """
  @behaviour Core.Component

  @map_size 2048.0

  @impl Core.Component
  def on_ready(world_ref) do
    Core.NifBridge.set_world_size(world_ref, @map_size, @map_size)
    :ok
  end
end
