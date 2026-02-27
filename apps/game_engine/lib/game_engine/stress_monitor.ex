defmodule GameEngine.StressMonitor do
  @moduledoc """
  独立したパフォーマンス監視プロセス。
  クラッシュしてもゲームは継続する（one_for_one 戦略）。
  """

  use GenServer
  require Logger

  @sample_interval_ms 1_000
  @frame_budget_ms    1000.0 / 60.0

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def get_stats, do: GenServer.call(__MODULE__, :get_stats)

  @impl true
  def init(_opts) do
    Process.send_after(self(), :sample, @sample_interval_ms)
    {:ok, %{samples: 0, peak_enemies: 0, peak_physics_ms: 0.0, overrun_count: 0, last_enemy_count: 0}}
  end

  @impl true
  def handle_call(:get_stats, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:sample, state) do
    Process.send_after(self(), :sample, @sample_interval_ms)
    {:noreply, sample_and_log(state)}
  end

  defp sample_and_log(state) do
    case GameEngine.FrameCache.get() do
      :empty ->
        state

      {:ok, %{enemy_count: enemy_count, bullet_count: bullet_count, physics_ms: physics_ms,
              hud_data: {hp, max_hp, score, elapsed_s}}} ->
        game_module = Application.get_env(:game_server, :current_game, GameContent.VampireSurvivor)
        wave = game_module.wave_label(elapsed_s)
        overrun = physics_ms > @frame_budget_ms

        new_state = %{state |
          samples:          state.samples + 1,
          peak_enemies:     max(state.peak_enemies, enemy_count),
          peak_physics_ms:  Float.round(max(state.peak_physics_ms, physics_ms), 2),
          overrun_count:    state.overrun_count + if(overrun, do: 1, else: 0),
          last_enemy_count: enemy_count,
        }

        hp_pct = if max_hp > 0, do: Float.round(hp / max_hp * 100, 1), else: 0.0
        log_fn = if overrun, do: &Logger.warning/1, else: &Logger.info/1

        log_fn.(
          "[STRESS] #{wave} | enemies=#{enemy_count}/#{new_state.peak_enemies} " <>
          "bullets=#{bullet_count} score=#{score} HP=#{hp_pct}% " <>
          "physics=#{Float.round(physics_ms, 2)}ms overruns=#{new_state.overrun_count}/#{new_state.samples}"
        )

        new_state
    end
  end
end
