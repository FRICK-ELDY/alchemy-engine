defmodule Contents.Components.Category.Rendering.Render do
  @moduledoc """
  描画の「実行」のみを担当する単一コンポーネント。

  Content の build_frame(playing_state, context) で組み立てられた
  {commands, camera, ui} を取得し、エンコード・送信・cursor_grab リセットを行う。
  「何を描くか」の定義は apps/contents/lib/contents 側（各 Content / Playing）にあり、
  本モジュールは取得・エンコード・送信のみを実行する。
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()

    if function_exported?(content, :build_frame, 2) do
      runner = content.flow_runner(:main)

      playing_state =
        (runner && Contents.Scenes.Stack.get_scene_state(runner, content.playing_scene())) || %{}

      current_scene =
        case runner && Contents.Scenes.Stack.current(runner) do
          {:ok, %{scene_type: st}} -> st
          _ -> content.playing_scene()
        end

      context_with_scene = Map.put(context, :current_scene, current_scene)
      {commands, camera, ui} = content.build_frame(playing_state, context_with_scene)

      mesh_definitions =
        if function_exported?(content, :mesh_definitions, 0),
          do: content.mesh_definitions(),
          else: []

      # ゲームオーバー等でボタンクリックが必要なシーンでは cursor_grab: :release を送る
      cursor_grab = resolve_cursor_grab(content, playing_state, current_scene)

      frame_binary =
        Content.FrameEncoder.encode_frame(
          commands,
          camera,
          ui,
          mesh_definitions,
          cursor_grab
        )

      Contents.FrameBroadcaster.put(context.room_id, frame_binary)

      cursor_grab_reset = Map.get(playing_state, :cursor_grab_request, :no_change)

      if cursor_grab_reset != :no_change and runner do
        Contents.Scenes.Stack.update_by_scene_type(
          runner,
          content.playing_scene(),
          &apply_cursor_grab_request(&1, cursor_grab_reset)
        )
      end
    end

    :ok
  end

  # フレームに含める cursor_grab。ゲームオーバー等では :release でボタンクリックを可能に。
  defp resolve_cursor_grab(content, playing_state, current_scene) do
    from_playing = Map.get(playing_state, :cursor_grab_request, :no_change)

    cond do
      from_playing != :no_change -> from_playing
      # ゲームオーバーシーンではカーソルを解放して RETRY 等のボタンをクリック可能に
      current_scene == content.game_over_scene() -> :release
      function_exported?(content, :scene_needs_cursor_release?, 1) and
          content.scene_needs_cursor_release?(current_scene) ->
        :release

      true -> :no_change
    end
  end

  defp apply_cursor_grab_request(state, cursor_grab) do
    if Map.get(state, :cursor_grab_request) == cursor_grab do
      Map.put(state, :cursor_grab_request, :no_change)
    else
      state
    end
  end
end
