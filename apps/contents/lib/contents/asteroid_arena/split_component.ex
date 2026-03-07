defmodule Content.AsteroidArena.SplitComponent do
  @moduledoc """
  小惑星撃破時の分裂処理・アイテムドロップを担うコンポーネント。

  - Large → Medium × 2
  - Medium → Small × 2
  - Small / UFO → Gem をドロップ
  - R-P2: on_nif_sync で enemy_damage_this_frame を注入
  """
  @behaviour Core.Component

  alias Content.AsteroidArena.SpawnSystem

  @item_gem 0

  # P5-1: frame_injection に enemy_damage_this_frame をマージ
  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()

    if function_exported?(content, :enemy_damage_this_frame, 1) do
      list = content.enemy_damage_this_frame(context)
      inj = Process.get(:frame_injection, %{})
      Process.put(:frame_injection, Map.put(inj, :enemy_damage_this_frame, list))
    end

    :ok
  end

  @impl Core.Component
  def on_event({:entity_removed, world_ref, kind_id, x, y}, _context) do
    SpawnSystem.handle_split(world_ref, kind_id, x, y)

    exp = SpawnSystem.exp_reward(kind_id)

    if exp > 0 do
      Core.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp)
    end

    :ok
  end

  def on_event(_event, _context), do: :ok
end
