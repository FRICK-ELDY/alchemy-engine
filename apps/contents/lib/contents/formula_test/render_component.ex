defmodule Content.FormulaTest.RenderComponent do
  @moduledoc """
  FormulaTest の描画コンポーネント。

  起動時に Contents.Nodes で実行した検証結果を HUD に表示する。
  全パターンが OK ならばノードアーキテクチャの動作検証が成功。
  """
  @behaviour Core.Component

  @color_ok {0.2, 0.8, 0.4, 1.0}
  @color_error {0.9, 0.3, 0.3, 1.0}
  @color_text {0.9, 0.95, 1.0, 1.0}
  @color_bg {0.05, 0.08, 0.12, 0.92}

  # グリッド頂点は固定のためキャッシュ。毎フレームの再生成を避ける
  @grid_vertices Content.MeshDef.grid_plane(
                   size: 20.0,
                   divisions: 20,
                   color: {0.25, 0.25, 0.3, 1.0}
                 )[:vertices]

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.SceneStack.get_scene_state(runner, content.playing_scene())) || %{}

    commands = build_commands()
    camera = build_camera()
    ui = build_ui(playing_state, context)

    cursor_grab = Map.get(playing_state, :cursor_grab_request, :no_change)

    frame_binary = Content.MessagePackEncoder.encode_frame(commands, camera, ui, [])
    Contents.FrameBroadcaster.put(context.room_id, frame_binary)

    if cursor_grab != :no_change and runner do
      Contents.SceneStack.update_by_scene_type(
        runner,
        content.playing_scene(),
        &clear_cursor_grab_if_matching(&1, cursor_grab)
      )
    end

    :ok
  end

  defp clear_cursor_grab_if_matching(state, cursor_grab) do
    if state.cursor_grab_request == cursor_grab do
      Map.put(state, :cursor_grab_request, :no_change)
    else
      state
    end
  end

  defp build_commands do
    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = {0.2, 0.4, 0.6, 1.0}
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = {0.5, 0.7, 0.95, 1.0}

    [
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}},
      {:grid_plane_verts, @grid_vertices}
    ]
  end

  defp build_camera do
    {:camera_3d, {0.0, 3.0, 8.0}, {0.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {60.0, 0.1, 200.0}}
  end

  defp build_ui(state, context) do
    results = Map.get(state, :formula_results, [])
    hud_visible = Map.get(state, :hud_visible, true)

    fps_text =
      if context.tick_ms > 0,
        do: "FPS: #{round(1000.0 / context.tick_ms)}",
        else: "FPS: --"

    result_lines = format_results(results)
    ok_count = Enum.count(results, fn {status, _, _} -> status == :ok end)
    total_count = length(results)
    summary = "Formula Test: #{ok_count}/#{total_count} OK"

    hud_nodes =
      if hud_visible do
        [
          {:node, {:center, {0.0, 0.0}, :wrap}, {:rect, @color_bg, 12.0, :none},
           [
             {:node, {:top_left, {0.0, 0.0}, :wrap},
              {:vertical_layout, 8.0, {24.0, 20.0, 24.0, 20.0}},
              [
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "Formula Engine Verification", @color_text, 24.0, true}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "Elixir -> Rust (NIF VM) -> Elixir", {0.7, 0.75, 0.85, 1.0}, 14.0,
                  false}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap}, {:text, summary, @color_text, 18.0, true},
                 []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, fps_text, {0.6, 0.65, 0.8, 1.0}, 14.0, false}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []}
              ] ++
                result_lines ++
                [
                  {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
                  {:node, {:top_left, {0.0, 0.0}, :wrap},
                   {:button, "  Quit  ", "__quit__", {0.55, 0.2, 0.2, 1.0}, 120.0, 36.0}, []}
                ]}
           ]}
        ]
      else
        []
      end

    {:canvas, hud_nodes}
  end

  defp format_results(results) do
    results
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{status, desc, value}, i} ->
      {r, g, b, a} = if status == :ok, do: @color_ok, else: @color_error
      status_str = if status == :ok, do: "OK", else: "ERR"
      value_str = format_value(value)

      [
        {:node, {:top_left, {0.0, 0.0}, :wrap},
         {:text, "#{i}. [#{status_str}] #{desc} => #{value_str}", {r, g, b, a}, 14.0, false}, []}
      ]
    end)
  end

  defp format_value(value) when is_list(value), do: inspect(value)
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value), do: inspect(value)
end
