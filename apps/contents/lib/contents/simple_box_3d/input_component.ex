defmodule Content.SimpleBox3D.InputComponent do
  @moduledoc """
  ウィンドウからの移動入力を受け取り、Playing シーン state に反映するコンポーネント。

  Rust 物理エンジンを使わない SimpleBox3D では、winit からの
  `{:move_input, dx, dy}` メッセージを直接シーン state に書き込む必要がある。
  `GameEvents` は `{:move_input, dx, dy}` を受信すると `on_frame_event/2` として
  各コンポーネントに配信するため、ここで `SceneManager` を更新する。
  """
  @behaviour Core.Component

  @impl Core.Component
  # dx, dy は Rust の on_move_input が f64 としてエンコードするため float で届く。
  def on_event({:move_input, dx, dy}, _context) when is_float(dx) and is_float(dy) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Content.SimpleBox3D.Scenes.Playing,
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
        Content.SimpleBox3D.Scenes.GameOver,
        fn state -> Map.put(state, :retry, true) end
      )
    end

    :ok
  end

  def on_event(_event, _context), do: :ok
end
