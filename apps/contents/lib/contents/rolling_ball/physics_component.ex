defmodule Content.RollingBall.PhysicsComponent do
  @moduledoc """
  RollingBall の入力受信コンポーネント。

  WASD 入力を Playing シーン state に反映する。
  物理演算（慣性・摩擦・落下判定）は Playing シーンの update で行う。
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_event({:move_input, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.RollingBall.Scenes.Playing,
        fn state -> Map.put(state, :move_input, {dx, dy}) end
      )
    end

    :ok
  end

  def on_event({:ui_action, "__retry__"}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.RollingBall.Scenes.GameOver,
        fn state -> Map.put(state, :retry, true) end
      )
    end

    :ok
  end

  def on_event({:ui_action, "__next_stage__"}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.RollingBall.Scenes.StageClear,
        fn state -> Map.put(state, :next, true) end
      )
    end

    :ok
  end

  def on_event({:ui_action, "__start__"}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.RollingBall.Scenes.Title,
        fn state -> Map.put(state, :start, true) end
      )
    end

    :ok
  end

  def on_event({:ui_action, "__back_to_title__"}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.RollingBall.Scenes.Ending,
        fn state -> Map.put(state, :back_to_title, true) end
      )
    end

    :ok
  end

  def on_event(_event, _context), do: :ok
end
