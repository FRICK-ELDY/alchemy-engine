defmodule GameEngine.Stats do
  @moduledoc """
  ゲームセッション統計をリアルタイム収集する GenServer。
  """

  use GenServer
  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def record_kill(enemy_kind, weapon_kind) do
    GenServer.cast(__MODULE__, {:kill, enemy_kind, weapon_kind})
  end

  def record_item_pickup(item_kind) do
    GenServer.cast(__MODULE__, {:item_pickup, item_kind})
  end

  def record_level_up(level) do
    GenServer.cast(__MODULE__, {:level_up, level})
  end

  def new_session do
    GenServer.cast(__MODULE__, :new_session)
  end

  def session_summary do
    GenServer.call(__MODULE__, :summary)
  end

  @impl true
  def init(_opts) do
    GameEngine.EventBus.subscribe()
    {:ok, initial_state()}
  end

  @impl true
  def handle_info({:game_events, events}, state) do
    new_state =
      Enum.reduce(events, state, fn
        {:enemy_killed, enemy_kind, weapon_kind}, acc ->
          acc
          |> Map.update(
            :kills_by_enemy,
            %{enemy_kind => 1},
            &Map.update(&1, enemy_kind, 1, fn n -> n + 1 end)
          )
          |> Map.update(
            :kills_by_weapon,
            %{weapon_kind => 1},
            &Map.update(&1, weapon_kind, 1, fn n -> n + 1 end)
          )
          |> Map.update(:total_kills, 1, &(&1 + 1))

        {:level_up_event, new_level, _}, acc ->
          Map.put(acc, :max_level_reached, new_level)

        {:item_pickup, item_kind, _}, acc ->
          Map.update(
            acc,
            :items_collected,
            %{item_kind => 1},
            &Map.update(&1, item_kind, 1, fn n -> n + 1 end)
          )

        _, acc ->
          acc
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:kill, enemy_kind, weapon_kind}, state) do
    kills_by_enemy = Map.update(state.kills_by_enemy, enemy_kind, 1, &(&1 + 1))
    kills_by_weapon = Map.update(state.kills_by_weapon, weapon_kind, 1, &(&1 + 1))

    {:noreply,
     %{
       state
       | kills_by_enemy: kills_by_enemy,
         kills_by_weapon: kills_by_weapon,
         total_kills: state.total_kills + 1
     }}
  end

  @impl true
  def handle_cast({:item_pickup, item_kind}, state) do
    items = Map.update(state.items_collected, item_kind, 1, &(&1 + 1))
    {:noreply, %{state | items_collected: items}}
  end

  @impl true
  def handle_cast({:level_up, level}, state) do
    {:noreply, %{state | max_level_reached: max(state.max_level_reached, level)}}
  end

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
      total_kills: state.total_kills,
      kills_by_enemy: state.kills_by_enemy,
      kills_by_weapon: state.kills_by_weapon,
      items_collected: state.items_collected,
      max_level_reached: state.max_level_reached
    }

    {:reply, summary, state}
  end

  defp initial_state do
    %{
      session_start_ms: System.monotonic_time(:millisecond),
      total_kills: 0,
      kills_by_enemy: %{},
      kills_by_weapon: %{},
      items_collected: %{},
      max_level_reached: 1
    }
  end
end
