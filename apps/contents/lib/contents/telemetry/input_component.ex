defmodule Content.Telemetry.InputComponent do
  @moduledoc """
  Telemetry の入力コンポーネント。

  WASD 移動・Shift ダッシュ・マウス操作（見渡し）を受け取り、Playing シーン state に反映する。
  ESC と Quit は MenuComponent が処理する。
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_event({:move_input, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    update_playing(fn state -> Map.put(state, :move_input, {dx, dy}) end)
    :ok
  end

  def on_event({:mouse_delta, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    update_playing(fn state -> Map.put(state, :mouse_delta, {dx, dy}) end)
    :ok
  end

  def on_event({:sprint, value}, _context) when is_boolean(value) do
    update_playing(fn state -> Map.put(state, :sprint, value) end)
    :ok
  end

  def on_event(_event, _context), do: :ok

  defp update_playing(fun) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(runner, content.playing_scene(), fun)
    end
  end
end
