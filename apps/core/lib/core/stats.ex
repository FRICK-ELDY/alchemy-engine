defmodule Core.Stats do
  @moduledoc """
  ゲームセッション統計をリアルタイム収集する GenServer。

  コンテンツ固有の語彙（kills / enemy / weapon 等）は持たない。
  contents は `increment/1`・`increment/2`・`set/2`、または EventBus 経由の
  `{:stat, key}` / `{:stat, key, n}` / `{:stat_set, key, value}` で記録する。
  """

  use GenServer
  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "カウンタ `key` を 1 増やす。"
  def increment(key), do: increment(key, 1)

  @doc "カウンタ `key` を `n` 増やす。"
  def increment(key, n) when is_number(n) do
    GenServer.cast(__MODULE__, {:increment, key, n})
  end

  @doc "値 `key` を `value` に設定する。"
  def set(key, value) do
    GenServer.cast(__MODULE__, {:set, key, value})
  end

  def new_session do
    GenServer.cast(__MODULE__, :new_session)
  end

  def session_summary do
    GenServer.call(__MODULE__, :summary)
  end

  @impl true
  def init(_opts) do
    Core.EventBus.subscribe()
    {:ok, initial_state()}
  end

  @impl true
  def handle_info({:game_events, events}, state) do
    new_state =
      Enum.reduce(events, state, fn
        {:stat, key}, acc ->
          bump(acc, key, 1)

        {:stat, key, n}, acc when is_number(n) ->
          bump(acc, key, n)

        {:stat_set, key, value}, acc ->
          put_value(acc, key, value)

        _, acc ->
          acc
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:increment, key, n}, state), do: {:noreply, bump(state, key, n)}

  @impl true
  def handle_cast({:set, key, value}, state), do: {:noreply, put_value(state, key, value)}

  @impl true
  def handle_cast(:new_session, _state) do
    Logger.info("[Stats] 新しいセッションを開始しました")
    {:noreply, initial_state()}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    elapsed_s = (System.monotonic_time(:millisecond) - state.session_start_ms) / 1000.0

    summary = %{
      elapsed_seconds: elapsed_s,
      counters: state.counters,
      values: state.values
    }

    {:reply, summary, state}
  end

  defp bump(state, key, n) do
    %{state | counters: Map.update(state.counters, key, n, &(&1 + n))}
  end

  defp put_value(state, key, value) do
    %{state | values: Map.put(state.values, key, value)}
  end

  defp initial_state do
    %{
      session_start_ms: System.monotonic_time(:millisecond),
      counters: %{},
      values: %{}
    }
  end
end
