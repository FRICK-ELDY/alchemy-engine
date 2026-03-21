defmodule Content.Tetris do
  @moduledoc """
  SimpleBox3D を参考にしたテトリスのサンプルコンテンツ。

  - A / D: 左右移動
  - W: 回転
  - S: ソフトドロップ
  """

  def components do
    [
      Contents.Components.Category.Spawner,
      Contents.Components.Category.Device.Mouse,
      Contents.Components.Category.Device.Keyboard,
      Contents.Components.Category.Rendering.Render
    ]
  end

  # 2D グリッドゲームだが、既存コンテンツと同様に十分大きい値を返しておく。
  def world_size, do: {2048.0, 2048.0}

  def build_frame(playing_state, context),
    do: Content.Tetris.Scenes.Playing.build_frame(playing_state, context)

  def mesh_definitions do
    [
      Contents.Components.Category.Procedural.Meshes.Box.mesh_def(),
      Contents.Components.Category.Procedural.Meshes.Quad.mesh_def()
    ]
  end

  def render_type, do: :playing

  def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def initial_scenes do
    [%{scene_type: :playing, init_arg: %{}}]
  end

  def physics_scenes do
    [:playing]
  end

  def playing_scene, do: :playing
  def game_over_scene, do: :game_over

  def scene_init(:playing, init_arg), do: Content.Tetris.Scenes.Playing.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.Tetris.Scenes.GameOver.init(init_arg)

  def scene_update(:playing, context, state) do
    Content.Tetris.Scenes.Playing.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:game_over, context, state) do
    Content.Tetris.Scenes.GameOver.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_render_type(:playing), do: :playing
  def scene_render_type(:game_over), do: :game_over

  defp map_transition_module_to_scene_type({:continue, state}), do: {:continue, state}

  defp map_transition_module_to_scene_type({:continue, state, opts}),
    do: {:continue, state, opts || %{}}

  defp map_transition_module_to_scene_type({:transition, :pop, state}),
    do: {:transition, :pop, state}

  defp map_transition_module_to_scene_type({:transition, :pop, state, opts}),
    do: {:transition, :pop, state, opts || %{}}

  defp map_transition_module_to_scene_type({:transition, {:push, mod, arg}, state}) do
    {:transition, {:push, scene_module_to_type(mod), arg}, state}
  end

  defp map_transition_module_to_scene_type({:transition, {:push, mod, arg}, state, opts}) do
    {:transition, {:push, scene_module_to_type(mod), arg}, state, opts || %{}}
  end

  defp map_transition_module_to_scene_type({:transition, {:replace, mod, arg}, state}) do
    {:transition, {:replace, scene_module_to_type(mod), arg}, state}
  end

  defp map_transition_module_to_scene_type({:transition, {:replace, mod, arg}, state, opts}) do
    {:transition, {:replace, scene_module_to_type(mod), arg}, state, opts || %{}}
  end

  defp scene_module_to_type(Content.Tetris.Scenes.Playing), do: :playing
  defp scene_module_to_type(Content.Tetris.Scenes.GameOver), do: :game_over
  defp scene_module_to_type(mod), do: raise("unknown scene module: #{inspect(mod)}")

  def title, do: "Tetris Sample"
  def version, do: "0.1.0"

  def assets_path, do: ""
  def context_defaults, do: %{}

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "Tetris #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end
end
