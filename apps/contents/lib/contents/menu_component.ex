defmodule Contents.MenuComponent do
  @moduledoc """
  メニュー UI を管理するコンポーネント。

  ESC でメニューの表示/非表示をトグルする。
  - メニュー表示中: マウスロックなし（Quit 等のボタンが押せる）
  - メニュー非表示中: マウスロック（ゲーム操作モード）

  起動時はメニュー表示で開始するため、すぐに Quit を押せる。
  """
  @behaviour Core.Component

  @table :menu_state

  @color_title {0.9, 0.95, 1.0, 1.0}
  @color_label {0.6, 0.7, 0.85, 1.0}
  @color_value {0.4, 0.9, 0.5, 1.0}
  @color_bg {0.05, 0.08, 0.12, 0.92}

  @impl true
  def on_ready(_world_ref) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @impl true
  def on_event({:key_pressed, :escape}, context) do
    room_id = Map.get(context, :room_id, :main)
    visible = not get_menu_visible(room_id)
    :ets.insert(@table, {{room_id, :visible}, visible})
    :ok
  end

  def on_event({:ui_action, "__quit__"}, _context) do
    Application.stop(:server)
    :ok
  end

  def on_event(_event, _context), do: :ok

  @impl true
  def on_nif_sync(_context), do: :ok

  @doc """
  room_id のメニュー表示状態を返す。true のときメニュー表示、マウスロックなし。

  未初期化時は true（起動時メニュー表示）を返す。
  """
  def get_menu_visible(room_id \\ :main) do
    case :ets.lookup(@table, {room_id, :visible}) do
      [{{^room_id, :visible}, v}] -> v
      [] -> true
    end
  end

  @doc """
  メニューの UI ノード（Quit ボタン・デバッグ表示）を返す。

  room_id と context から TelemetryComponent の入力状態等を読み取り、
  メニューパネル用の canvas ノードリストを返す。
  """
  def get_menu_ui(room_id, context) do
    room_id = room_id || :main

    fps_text =
      if context.tick_ms > 0,
        do: "FPS: #{round(1000.0 / context.tick_ms)}",
        else: "FPS: --"

    input = Contents.TelemetryComponent.get_input_state(room_id)
    keyboard_str = input.keyboard
    mouse_map = input.mouse

    x_str = format_opt(mouse_map.x)
    y_str = format_opt(mouse_map.y)
    dx_str = format_float(mouse_map.delta_x)
    dy_str = format_float(mouse_map.delta_y)
    mouse_display = "x: #{x_str}, y: #{y_str}, delta: {x: #{dx_str}, y: #{dy_str}}"

    [
      {:node, {:center, {0.0, 0.0}, :wrap}, {:rect, @color_bg, 18.0, :none},
       [
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:vertical_layout, 15.0, {36.0, 30.0, 36.0, 30.0}},
          [
            {:node, {:top_left, {0.0, 0.0}, :wrap}, {:text, "Menu", @color_title, 25.0, true},
             []},
            {:node, {:top_left, {0.0, 0.0}, :wrap}, {:text, fps_text, @color_label, 15.0, false},
             []},
            {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text, "keyboard: \"#{keyboard_str}\"", @color_value, 14.0, false}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text, "mouse: { #{mouse_display} }", @color_value, 14.0, false}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:text, "ESC: toggle menu", @color_label, 13.0, false}, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:button, "  Quit  ", "__quit__", {0.55, 0.2, 0.2, 1.0}, 180.0, 54.0}, []}
          ]}
       ]}
    ]
  end

  defp format_opt(nil), do: "—"
  defp format_opt(v) when is_number(v), do: format_float(v)

  defp format_float(v) when is_number(v) do
    v |> Float.round(2) |> to_string()
  end
end
