defmodule Core.StressMonitor do
  @moduledoc """
  独立したパフォーマンス監視プロセス。
  クラッシュしてもゲームは継続する（one_for_one 戦略）。

  統計はルーム別に `state.rooms` へ保持する。
  後方互換のため、`:main` ルームの統計をトップレベルにもミラーする。
  """

  use GenServer
  require Logger

  @sample_interval_ms 1_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def get_stats, do: GenServer.call(__MODULE__, :get_stats)

  @impl true
  def init(_opts) do
    Process.send_after(self(), :sample, @sample_interval_ms)
    {:ok, initial_state()}
  end

  @impl true
  def handle_call(:get_stats, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:sample, state) do
    Process.send_after(self(), :sample, @sample_interval_ms)
    {:noreply, sample_and_log(state)}
  end

  defp initial_state do
    empty_room_stats()
    |> Map.put(:rooms, %{})
  end

  defp empty_room_stats do
    %{samples: 0, peak_enemies: 0, peak_physics_ms: 0.0, overrun_count: 0, last_enemy_count: 0}
  end

  defp sample_and_log(state) do
    entries = Core.FrameCache.list()
    active_ids = MapSet.new(Enum.map(entries, fn {room_id, _} -> room_id end))

    state
    |> then(fn s -> Enum.reduce(entries, s, &sample_room/2) end)
    |> prune_inactive_rooms(active_ids)
    |> mirror_main_stats()
  end

  defp sample_room(
         {room_id,
          %{
            enemy_count: enemy_count,
            bullet_count: bullet_count,
            physics_ms: physics_ms,
            hud_data: {hp, max_hp, score, elapsed_s}
          }},
         state
       ) do
    content_module = Core.Config.current()
    wave = content_module.wave_label(elapsed_s)
    frame_budget_ms = Core.Config.tick_ms() * 1.0
    physics_ms_f = physics_ms * 1.0
    overrun? = physics_ms_f > frame_budget_ms

    room_stats = Map.get(state.rooms, room_id, empty_room_stats())

    new_room_stats = %{
      room_stats
      | samples: room_stats.samples + 1,
        peak_enemies: max(room_stats.peak_enemies, enemy_count),
        peak_physics_ms: Float.round(max(room_stats.peak_physics_ms, physics_ms_f), 2),
        overrun_count: room_stats.overrun_count + if(overrun?, do: 1, else: 0),
        last_enemy_count: enemy_count
    }

    hp_pct = if max_hp > 0, do: Float.round(hp / max_hp * 100, 1), else: 0.0
    log_fn = if overrun?, do: &Logger.warning/1, else: &Logger.info/1

    log_fn.(
      "[STRESS] room=#{inspect(room_id)} #{wave} | " <>
        "enemies=#{enemy_count}/#{new_room_stats.peak_enemies} " <>
        "bullets=#{bullet_count} score=#{score} HP=#{hp_pct}% " <>
        "physics=#{Float.round(physics_ms_f, 2)}ms " <>
        "overruns=#{new_room_stats.overrun_count}/#{new_room_stats.samples}"
    )

    %{state | rooms: Map.put(state.rooms, room_id, new_room_stats)}
  end

  defp sample_room(_entry, state), do: state

  defp prune_inactive_rooms(state, active_ids) do
    rooms =
      state.rooms
      |> Enum.filter(fn {room_id, _} -> MapSet.member?(active_ids, room_id) end)
      |> Map.new()

    %{state | rooms: rooms}
  end

  # 後方互換: :main のルーム統計をトップレベルへミラーする
  defp mirror_main_stats(state) do
    case Map.get(state.rooms, :main) do
      nil ->
        Map.merge(state, empty_room_stats())

      main_stats ->
        Map.merge(state, Map.take(main_stats, Map.keys(empty_room_stats())))
    end
  end
end
