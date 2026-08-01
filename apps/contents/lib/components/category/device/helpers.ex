defmodule Contents.Components.Category.Device.Helpers do
  @moduledoc """
  Device コンポーネント（Mouse, Keyboard 等）で共有するヘルパー。

  playing シーン state の更新など、共通ロジックを提供する。
  """
  @doc """
  指定した scene_type のシーン state に fun を適用して更新する。

  runner（flow_runner）が nil の場合は何もしない。
  room_id 省略時は `:main`（後方互換）。
  """
  @spec with_scene_type(atom(), (map() -> map())) :: :ok
  def with_scene_type(scene_type, fun) when is_atom(scene_type) and is_function(fun, 1) do
    with_scene_type(:main, scene_type, fun)
  end

  @spec with_scene_type(term(), atom(), (map() -> map())) :: :ok
  def with_scene_type(room_id, scene_type, fun)
      when is_atom(scene_type) and is_function(fun, 1) do
    content = Core.Config.current()
    runner = content.flow_runner(room_id)

    if runner do
      Contents.Scenes.Stack.update_by_scene_type(runner, scene_type, fun)
    end

    :ok
  end

  @doc """
  現在の Content の playing シーン state に fun を適用して更新する。

  runner（flow_runner）が nil の場合は何もしない。
  room_id 省略時は `:main`（後方互換）。
  """
  @spec with_playing_scene((map() -> map())) :: :ok
  def with_playing_scene(fun) when is_function(fun, 1) do
    with_playing_scene(:main, fun)
  end

  @spec with_playing_scene(term(), (map() -> map())) :: :ok
  def with_playing_scene(room_id, fun) when is_function(fun, 1) do
    content = Core.Config.current()
    with_scene_type(room_id, content.playing_scene(), fun)
  end
end
