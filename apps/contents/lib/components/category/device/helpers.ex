defmodule Contents.Components.Category.Device.Helpers do
  @moduledoc """
  Device コンポーネント（Mouse, Keyboard 等）で共有するヘルパー。

  playing シーン state の更新など、共通ロジックを提供する。
  """
  @doc """
  現在の Content の playing シーン state に fun を適用して更新する。

  runner（flow_runner）が nil の場合は何もしない。
  """
  @spec with_playing_scene((map() -> map())) :: :ok
  def with_playing_scene(fun) when is_function(fun, 1) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.Scenes.Stack.update_by_scene_type(
        runner,
        content.playing_scene(),
        fun
      )
    end

    :ok
  end
end
