defmodule Core.StressMonitor do
  @moduledoc """
  独立したパフォーマンス監視プロセス。
  クラッシュしてもゲームは継続する（one_for_one 戦略）。

  `Core.FrameCache` の汎用スナップショット（`:physics_ms` / `:label` / `:counters` / `:meta`）
  のみを参照する。コンテンツモジュールや wave / enemy 等の語彙には依存しない。

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
    %{samples: 0, peak_physics_ms: 0.0, overrun_count: 0, peak_counters: %{}, last_counters: %{}}
  end

  defp sample_and_log(state) do
    entries = Core.FrameCache.list()
    active_ids = MapSet.new(Enum.map(entries, fn {room_id, _} -> room_id end))

    state
    |> then(fn s -> Enum.reduce(entries, s, &sample_room/2) end)
    |> prune_inactive_rooms(active_ids)
    |> mirror_main_stats()
  end

  defp sample_room({room_id, snapshot}, state) when is_map(snapshot) do
    case Map.fetch(snapshot, :physics_ms) do
      :error ->
        state

      {:ok, physics_ms} ->
        label = Map.get(snapshot, :label, "")
        counters = normalize_counters(Map.get(snapshot, :counters, %{}))
        meta = Map.get(snapshot, :meta, %{})
        frame_budget_ms = Core.Config.tick_ms() * 1.0
        physics_ms_f = physics_ms_to_float(physics_ms)
        overrun? = physics_ms_f > frame_budget_ms

        room_stats = Map.get(state.rooms, room_id, empty_room_stats())

        new_room_stats = %{
          room_stats
          | samples: room_stats.samples + 1,
            peak_physics_ms: Float.round(max(room_stats.peak_physics_ms, physics_ms_f), 2),
            overrun_count: room_stats.overrun_count + if(overrun?, do: 1, else: 0),
            peak_counters: merge_peak_counters(room_stats.peak_counters, counters),
            last_counters: counters
        }

        log_fn = if overrun?, do: &Logger.warning/1, else: &Logger.info/1

        log_fn.(
          "[STRESS] room=#{inspect(room_id)}" <>
            label_part(label) <>
            " | " <>
            counters_part(counters, new_room_stats.peak_counters) <>
            meta_part(meta) <>
            "physics=#{Float.round(physics_ms_f, 2)}ms " <>
            "overruns=#{new_room_stats.overrun_count}/#{new_room_stats.samples}"
        )

        %{state | rooms: Map.put(state.rooms, room_id, new_room_stats)}
    end
  end

  defp sample_room(_entry, state), do: state

  defp normalize_counters(counters) when is_map(counters), do: counters
  defp normalize_counters(_), do: %{}

  defp merge_peak_counters(peaks, counters) do
    Enum.reduce(counters, peaks, fn {key, value}, acc ->
      if is_number(value) do
        Map.update(acc, key, value, &max(&1, value))
      else
        acc
      end
    end)
  end

  defp label_part(""), do: ""
  defp label_part(label) when is_binary(label), do: " #{label}"
  defp label_part(label), do: " #{inspect(label)}"

  defp counters_part(counters, _peaks) when map_size(counters) == 0, do: ""

  defp counters_part(counters, peaks) do
    Enum.map_join(counters, " ", fn {key, value} ->
      peak = Map.get(peaks, key, value)
      "#{key}=#{value}/#{peak}"
    end) <> " "
  end

  defp meta_part(meta) when not is_map(meta) or map_size(meta) == 0, do: ""

  defp meta_part(meta) do
    Enum.map_join(meta, " ", fn {key, value} -> "#{key}=#{format_meta_value(value)}" end) <> " "
  end

  defp format_meta_value(v) when is_float(v), do: Float.round(v, 1)
  defp format_meta_value(v), do: v

  defp physics_ms_to_float(n) when is_number(n), do: n * 1.0
  defp physics_ms_to_float(_), do: 0.0

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
