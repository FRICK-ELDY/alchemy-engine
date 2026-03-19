defmodule Contents.LocalUserComponent do
  @moduledoc """
  デフォルトのローカルユーザー入力コンポーネント。

  全コンテンツ共通のキーマッピング（WASD/矢印→move、Shift→sprint、Escape→key_pressed）で
  raw_key, raw_mouse_motion, focus_lost を処理する。
  Zenoh / Phoenix Channel / UDP 等のネットワーク経由の {:move_input, dx, dy} も受け付け、
  ETS に保存して get_move_vector/1 から参照可能にする。

  コンテンツが local_user_input_module/0 を実装しない場合に使用される。
  """
  @behaviour Core.Component

  @table :local_user_input

  @impl true
  def on_ready(_world_ref) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @impl true
  def on_event({:raw_key, key, key_state}, context) when key_state in [:pressed, :released] do
    room_id = Map.get(context, :room_id, :main)
    keys_held = get_keys_held_private(room_id)

    {new_keys, new_sprint} =
      case key_state do
        :pressed ->
          new_keys = MapSet.put(keys_held, key)
          {new_keys, sprint_from_keys(new_keys)}

        :released ->
          new_keys = MapSet.delete(keys_held, key)
          {new_keys, sprint_from_keys(new_keys)}
      end

    {dx, dy} = move_vector_from_keys(new_keys)
    prev_sprint = get_sprint_private(room_id)

    :ets.insert(@table, {{room_id, :keys_held}, new_keys})
    :ets.insert(@table, {{room_id, :sprint}, new_sprint})
    :ets.insert(@table, {{room_id, :move}, {dx, dy}})

    handler = get_event_handler(context, room_id)

    if handler do
      send(handler, {:move_input, dx * 1.0, dy * 1.0})

      if new_sprint != prev_sprint do
        send(handler, {:sprint, new_sprint})
      end

      if key == :escape and key_state == :pressed do
        send(handler, {:key_pressed, :escape})
      end
    end

    :ok
  end

  def on_event({:mouse_delta, dx, dy}, context) when is_float(dx) and is_float(dy) do
    room_id = Map.get(context, :room_id, :main)
    :ets.insert(@table, {{room_id, :mouse_delta}, {dx, dy}})
    :ok
  end

  def on_event({:cursor_position, x, y}, context) when is_number(x) and is_number(y) do
    room_id = Map.get(context, :room_id, :main)
    :ets.insert(@table, {{room_id, :mouse_pos}, {x * 1.0, y * 1.0}})
    :ok
  end

  def on_event({:move_input, dx, dy}, context) when is_number(dx) and is_number(dy) do
    room_id = Map.get(context, :room_id, :main)
    :ets.insert(@table, {{room_id, :move}, {dx * 1.0, dy * 1.0}})
    # [DEBUG]
    require Logger
    Logger.info("[input:LocalUserComponent] on_event {:move_input, #{dx}, #{dy}} → ETS insert room=#{inspect(room_id)}")
    :ok
  end

  def on_event(:focus_lost, context) do
    room_id = Map.get(context, :room_id, :main)
    prev_sprint = get_sprint_private(room_id)

    :ets.insert(@table, {{room_id, :keys_held}, MapSet.new()})
    :ets.insert(@table, {{room_id, :sprint}, false})
    :ets.insert(@table, {{room_id, :move}, {0, 0}})
    :ets.insert(@table, {{room_id, :mouse_delta}, {0.0, 0.0}})

    handler = get_event_handler(context, room_id)
    if handler, do: send(handler, {:move_input, 0.0, 0.0})
    if handler && prev_sprint, do: send(handler, {:sprint, false})

    :ok
  end

  def on_event(_event, _context), do: :ok

  @impl true
  def on_nif_sync(_context), do: :ok

  def get_move_vector(room_id) do
    case :ets.lookup(@table, {room_id, :move}) do
      [{{^room_id, :move}, vec}] -> vec
      [] -> {0, 0}
    end
  end

  @doc """
  room_id に対応する押下中のキー一覧を返す。
  """
  def get_keys_held(room_id) do
    case :ets.lookup(@table, {room_id, :keys_held}) do
      [{{^room_id, :keys_held}, keys}] -> keys
      [] -> MapSet.new()
    end
  end

  @doc """
  room_id に対応するマウス状態を返す。%{x: float|nil, y: float|nil, delta_x: float, delta_y: float}
  """
  def get_mouse(room_id) do
    pos =
      case :ets.lookup(@table, {room_id, :mouse_pos}) do
        [{{^room_id, :mouse_pos}, {px, py}}] -> {px, py}
        _ -> {nil, nil}
      end

    delta =
      case :ets.lookup(@table, {room_id, :mouse_delta}) do
        [{{^room_id, :mouse_delta}, {dx, dy}}] -> {dx, dy}
        _ -> {0.0, 0.0}
      end

    {px, py} = pos
    {dx, dy} = delta

    %{x: px, y: py, delta_x: dx, delta_y: dy}
  end

  @doc """
  room_id に対応するクライアント情報を返す。
  ZenohBridge が contents/room/{id}/client/info を受信すると :client_info ETS に格納される。
  未受信時は nil。%{os: "windows", arch: "x86_64", family: "windows"} 等。

  room_id は `:main` または binary を想定する。ZenohBridge はキー式から常に文字列を受け取るため、
  ETS のキーは `:main` と `"main"` を正規化して `:main` に統一する。
  """
  def get_client_info(room_id) do
    room_key = normalize_room_id_for_client_info(room_id)

    if :ets.whereis(:client_info) == :undefined do
      nil
    else
      case :ets.lookup(:client_info, {room_key, :info}) do
        [{{^room_key, :info}, info}] -> info
        [] -> nil
      end
    end
  end

  defp normalize_room_id_for_client_info(:main), do: :main
  defp normalize_room_id_for_client_info("main"), do: :main
  defp normalize_room_id_for_client_info(id) when is_binary(id), do: id
  defp normalize_room_id_for_client_info(id) when is_atom(id), do: id

  defp get_keys_held_private(room_id) do
    case :ets.lookup(@table, {room_id, :keys_held}) do
      [{{^room_id, :keys_held}, keys}] -> keys
      [] -> MapSet.new()
    end
  end

  defp get_sprint_private(room_id) do
    case :ets.lookup(@table, {room_id, :sprint}) do
      [{{^room_id, :sprint}, v}] -> v
      [] -> false
    end
  end

  defp sprint_from_keys(keys_held) do
    MapSet.member?(keys_held, :shift_left) or MapSet.member?(keys_held, :shift_right)
  end

  defp move_vector_from_keys(keys_held) do
    dx =
      if(MapSet.member?(keys_held, :d) or MapSet.member?(keys_held, :arrow_right), do: 1, else: 0) +
        if MapSet.member?(keys_held, :a) or MapSet.member?(keys_held, :arrow_left),
          do: -1,
          else: 0

    dy =
      if(MapSet.member?(keys_held, :s) or MapSet.member?(keys_held, :arrow_down), do: 1, else: 0) +
        if MapSet.member?(keys_held, :w) or MapSet.member?(keys_held, :arrow_up),
          do: -1,
          else: 0

    {dx, dy}
  end

  defp get_event_handler(context, room_id) do
    case Map.get(context, :event_handler) do
      pid when is_pid(pid) ->
        pid

      _ ->
        content = Core.Config.current()
        content.event_handler(room_id)
    end
  end
end
