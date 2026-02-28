defmodule GameContent.AsteroidArena.SplitComponent do
  @moduledoc """
  小惑星撃破時の分裂処理・アイテムドロップを担うコンポーネント。

  - Large → Medium × 2
  - Medium → Small × 2
  - Small / UFO → Gem をドロップ
  """
  @behaviour GameEngine.Component

  alias GameContent.AsteroidArena.SpawnSystem

  @item_gem 0

  @impl GameEngine.Component
  def on_event({:entity_removed, world_ref, kind_id, x, y}, _context) do
    SpawnSystem.handle_split(world_ref, kind_id, x, y)

    exp = SpawnSystem.exp_reward(kind_id)
    if exp > 0 do
      GameEngine.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp)
    end

    :ok
  end

  def on_event(_event, _context), do: :ok
end
