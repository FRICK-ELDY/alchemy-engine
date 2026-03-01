defmodule GameEngine.EventBus do
  @moduledoc """
  フレームイベントを受け取り、複数のサブスクライバーに配信する。
  """

  use GenServer
  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def subscribe(pid \\ self()) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  def broadcast(events) when is_list(events) do
    GenServer.cast(__MODULE__, {:broadcast, events})
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscribers: MapSet.new()}}
  end

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    {:noreply, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_cast({:broadcast, events}, state) do
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:game_events, events})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end
end
