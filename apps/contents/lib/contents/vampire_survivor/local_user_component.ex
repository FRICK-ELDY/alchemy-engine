defmodule Content.VampireSurvivor.LocalUserComponent do
  @moduledoc """
  ローカルユーザーのキーボード・マウス入力を管理するコンポーネント。

  raw_key, raw_mouse_motion, focus_lost を受け取り、
  コンテンツ内で move_input, sprint, key_pressed として利用する。
  """
  @behaviour Core.Component

  @table :local_user_input

  # ── on_ready: ETS テーブル作成 ───────────────────────────────────────

  @impl true
  def on_ready(_world_ref) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  # ── on_event: raw_key / mouse_delta / focus_lost ─────────────────────

  @impl true
  def on_event({:raw_key, key, key_state}, context) when key_state in [:pressed, :released] do
    room_id = Map.get(context, :room_id, :main)
    keys_held = get_keys_held(room_id)

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
    prev_sprint = get_sprint(room_id)

    :ets.insert(@table, {{room_id, :keys_held}, new_keys})
    :ets.insert(@table, {{room_id, :sprint}, new_sprint})
    :ets.insert(@table, {{room_id, :move}, {dx, dy}})

    # 意味論的イベントの配信（LevelUp 等で key_pressed が必要）
    handler = get_event_handler(context, room_id)

    if handler do
      send(handler, {:move_input, dx * 1.0, dy * 1.0})

      # InputHandler と同様、変化時のみ送信して無駄なメッセージを防ぐ
      if new_sprint != prev_sprint do
        send(handler, {:sprint, new_sprint})
      end

      if key == :escape and key_state == :pressed do
        send(handler, {:key_pressed, :escape})
      end
    end

    :ok
  end

  # ドキュメント目的: 当コンポーネントが {:mouse_delta, dx, dy} を受信することを明示。
  # vampire_survivor はマウス移動を使わないため空実装。将来の拡張用。
  def on_event({:mouse_delta, _dx, _dy}, _context), do: :ok

  def on_event(:focus_lost, context) do
    room_id = Map.get(context, :room_id, :main)
    prev_sprint = get_sprint(room_id)

    :ets.insert(@table, {{room_id, :keys_held}, MapSet.new()})
    :ets.insert(@table, {{room_id, :sprint}, false})
    :ets.insert(@table, {{room_id, :move}, {0, 0}})

    handler = get_event_handler(context, room_id)
    if handler, do: send(handler, {:move_input, 0.0, 0.0})
    if handler && prev_sprint, do: send(handler, {:sprint, false})

    :ok
  end

  def on_event(_event, _context), do: :ok

  # ── on_nif_sync: player_input は maybe_set_input_and_broadcast で投入済み ─

  @impl true
  def on_nif_sync(_context), do: :ok

  # ── 公開 API（GameEvents の maybe_set_input_and_broadcast から呼ばれる）──

  @doc """
  room_id に対応する移動ベクトルを返す。
  """
  def get_move_vector(room_id) do
    case :ets.lookup(@table, {room_id, :move}) do
      [{{^room_id, :move}, vec}] -> vec
      [] -> {0, 0}
    end
  end

  # ── 内部ヘルパー ────────────────────────────────────────────────────

  defp get_keys_held(room_id) do
    case :ets.lookup(@table, {room_id, :keys_held}) do
      [{{^room_id, :keys_held}, keys}] -> keys
      [] -> MapSet.new()
    end
  end

  defp get_sprint(room_id) do
    case :ets.lookup(@table, {room_id, :sprint}) do
      [{{^room_id, :sprint}, v}] -> v
      [] -> false
    end
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

  defp sprint_from_keys(keys_held) do
    MapSet.member?(keys_held, :shift_left) or MapSet.member?(keys_held, :shift_right)
  end

  # build_context は event_handler を設定していないため、
  # 現状は常に content.event_handler(room_id) が使用される。
  # 将来 context に event_handler を載せる設計に変更する場合はここで分岐する。
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
