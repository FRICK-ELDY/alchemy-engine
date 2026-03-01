defmodule GameEngine.InputHandler do
  @moduledoc """
  キー入力状態を ETS に書き込む GenServer。
  GameEvents は tick のたびに ETS から読み取る（ポーリング方式）。
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

  def key_down(key), do: GenServer.cast(__MODULE__, {:key_down, key})
  def key_up(key), do: GenServer.cast(__MODULE__, {:key_up, key})

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(@table, {:move, {0, 0}})
    {:ok, %{keys_held: MapSet.new()}}
  end

  @impl true
  def handle_cast({:key_down, key}, state) do
    if MapSet.member?(state.keys_held, key) do
      {:noreply, state}
    else
      new_keys = MapSet.put(state.keys_held, key)
      write_move_vector(new_keys)
      {:noreply, %{state | keys_held: new_keys}}
    end
  end

  @impl true
  def handle_cast({:key_up, key}, state) do
    if MapSet.member?(state.keys_held, key) do
      new_keys = MapSet.delete(state.keys_held, key)
      write_move_vector(new_keys)
      {:noreply, %{state | keys_held: new_keys}}
    else
      {:noreply, state}
    end
  end

  defp write_move_vector(keys_held) do
    dx =
      if(MapSet.member?(keys_held, :d) or MapSet.member?(keys_held, :arrow_right), do: 1, else: 0) +
        if MapSet.member?(keys_held, :a) or MapSet.member?(keys_held, :arrow_left),
          do: -1,
          else: 0

    dy =
      if(MapSet.member?(keys_held, :s) or MapSet.member?(keys_held, :arrow_down), do: 1, else: 0) +
        if MapSet.member?(keys_held, :w) or MapSet.member?(keys_held, :arrow_up), do: -1, else: 0

    :ets.insert(@table, {:move, {dx, dy}})
  end
end
