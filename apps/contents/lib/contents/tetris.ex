defmodule Content.Tetris do
  @moduledoc """
  Classic Tetris-style content.

  Scenes: `:title` -> `:playing` -> `:game_over`.

  - Title: START to begin
  - Play: WASD / arrow keys, score and line clears
  - Game over: RETRY to play again

  Rendering lives in `Content.Tetris.Frame`; `build_frame` reads scene state from the stack.

  Escape is handled by the shared Keyboard component (HUD / cursor grab). This content does not
  draw a HUD from that state, so the effect may be invisible compared to CanvasTest.
  """

  @behaviour Contents.Behaviour.Content

  def components do
    [
      Contents.Components.Category.Device.Mouse,
      Contents.Components.Category.Device.Keyboard,
      Contents.Components.Category.Rendering.Render
    ]
  end

  def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)

  def event_handler(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} -> pid
      :error -> nil
    end
  end

  def build_frame(_playing_state, context) do
    Content.Tetris.Frame.build(context)
  end

  def initial_scenes do
    [%{scene_type: :title, init_arg: %{}}]
  end

  def physics_scenes do
    []
  end

  def playing_scene, do: :playing
  def game_over_scene, do: :game_over

  def scene_init(:title, init_arg), do: Content.Tetris.Title.init(init_arg)
  def scene_init(:playing, init_arg), do: Content.Tetris.Playing.init(init_arg)
  def scene_init(:game_over, init_arg), do: Content.Tetris.GameOver.init(init_arg)

  def scene_update(:title, context, state) do
    Content.Tetris.Title.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:playing, context, state) do
    Content.Tetris.Playing.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_update(:game_over, context, state) do
    Content.Tetris.GameOver.update(context, state)
    |> map_transition_module_to_scene_type()
  end

  def scene_render_type(:title), do: :title
  def scene_render_type(:playing), do: :playing
  def scene_render_type(:game_over), do: :game_over

  # ContentBehaviour の全遷移パターンに対応（Tetris シーンは continue / replace のみ返すが、契約と一致させる）。
  @doc false
  defp map_transition_module_to_scene_type(result) do
    case result do
      {:continue, _, _} = x ->
        x

      {:continue, _} = x ->
        x

      {:transition, {:replace, target, arg}, state, opts} ->
        {:transition, {:replace, replace_target_to_scene_type(target), arg}, state, opts}

      {:transition, {:replace, target, arg}, state} ->
        {:transition, {:replace, replace_target_to_scene_type(target), arg}, state}

      {:transition, _, _, _} = x ->
        x

      {:transition, _, _} = x ->
        x

      other ->
        other
    end
  end

  defp replace_target_to_scene_type(t) when t in [:title, :playing, :game_over], do: t

  defp replace_target_to_scene_type(mod), do: scene_module_to_type(mod)

  defp scene_module_to_type(Content.Tetris.Title), do: :title
  defp scene_module_to_type(Content.Tetris.Playing), do: :playing
  defp scene_module_to_type(Content.Tetris.GameOver), do: :game_over
  defp scene_module_to_type(mod), do: raise("unknown scene module: #{inspect(mod)}")

  def title, do: "Tetris"
  def version, do: "0.1.0"

  def assets_path, do: ""

  def mesh_definitions do
    [
      Contents.Components.Category.Procedural.Meshes.Box.mesh_def(),
      Contents.Components.Category.Procedural.Meshes.Quad.mesh_def()
    ]
  end

  def context_defaults, do: %{}

  def wave_label(elapsed_sec) do
    minutes = trunc(elapsed_sec / 60)
    seconds = trunc(elapsed_sec) |> rem(60)

    "Tetris #{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end

  @doc """
  Title needs cursor release so the START button is clickable.
  """
  def scene_needs_cursor_release?(:title), do: true
  def scene_needs_cursor_release?(_), do: false

  def ui_action_handlers do
    %{
      "__start__" => {:title, fn s -> Map.put(s, :start, true) end}
    }
  end
end
