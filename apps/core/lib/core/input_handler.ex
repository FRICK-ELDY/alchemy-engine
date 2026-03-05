defmodule Core.InputHandler do
  @moduledoc """
  生キー入力（raw_key）を受け取り、意味論的イベントに変換する GenServer。

  Rust から `{:raw_key, key, state}` が届き、キー→意味のマッピングをここで行う。
  変換結果（move_input, sprint, key_pressed）を GameEvents に送信する。

  ## キーマッピング
  - WASD / 矢印キー → move_input (dx, dy)
  - Shift → sprint
  - Escape → key_pressed (:escape)

  ## 設計原則（implementation.mdc）
  - Elixir = SSoT：キー→意味のマッピングは Elixir 側が持つ
  - Rust = 演算層：生イベント取得・転送のみ
  """

  use GenServer

  @table :input_state

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def get_move_vector do
    case :ets.lookup(@table, :move) do
      [{:move, vec}] -> vec
      [] -> {0, 0}
    end
  end

  @doc """
  Rust から届く生キーイベント。
  GameEvents が受信してここに転送する。
  """
  def raw_key(key, key_state), do: GenServer.cast(__MODULE__, {:raw_key, key, key_state})

  @doc """
  フォーカス喪失時。Rust から届く。
  押下状態をすべてリセットする。
  """
  def focus_lost, do: GenServer.cast(__MODULE__, :focus_lost)

  # 後方互換: 既存の key_down/key_up は raw_key に委譲
  def key_down(key), do: raw_key(key, :pressed)
  def key_up(key), do: raw_key(key, :released)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(@table, {:move, {0, 0}})
    {:ok, %{keys_held: MapSet.new(), sprint: false}}
  end

  @impl true
  def handle_cast({:raw_key, key, key_state}, state_data) do
    {new_keys, new_sprint} = apply_key_change(key, key_state, state_data)
    emit_semantic_events(state_data, new_keys, new_sprint, key, key_state)
    {:noreply, %{state_data | keys_held: new_keys, sprint: new_sprint}}
  end

  def handle_cast(:focus_lost, state_data) do
    emit_semantic_events(state_data, MapSet.new(), false, nil, nil)
    {:noreply, %{state_data | keys_held: MapSet.new(), sprint: false}}
  end

  defp apply_key_change(key, :pressed, state_data) do
    new_keys = MapSet.put(state_data.keys_held, key)
    new_sprint = sprint_from_keys(new_keys)
    {new_keys, new_sprint}
  end

  defp apply_key_change(key, :released, state_data) do
    new_keys = MapSet.delete(state_data.keys_held, key)
    new_sprint = sprint_from_keys(new_keys)
    {new_keys, new_sprint}
  end

  defp sprint_from_keys(keys_held) do
    MapSet.member?(keys_held, :shift_left) or MapSet.member?(keys_held, :shift_right)
  end

  defp emit_semantic_events(prev_state, new_keys, new_sprint, key, key_state) do
    handler = event_handler()

    if handler do
      # move_input
      {dx, dy} = move_vector_from_keys(new_keys)
      :ets.insert(@table, {:move, {dx, dy}})
      send(handler, {:move_input, dx * 1.0, dy * 1.0})

      # sprint
      if new_sprint != prev_state.sprint do
        send(handler, {:sprint, new_sprint})
      end

      # key_pressed (Escape のみ、押下時のみ)
      if key == :escape and key_state == :pressed do
        send(handler, {:key_pressed, :escape})
      end
    else
      {dx, dy} = move_vector_from_keys(new_keys)
      :ets.insert(@table, {:move, {dx, dy}})
    end
  end

  defp event_handler do
    content = Core.Config.current()

    case content.event_handler(:main) do
      pid when is_pid(pid) -> pid
      _ -> nil
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
end
