defmodule GameEngine.GameEvents.Diagnostics do
  @moduledoc false

  require Logger

  @tick_ms 16

  @doc "replace 遷移時の init_arg を構築する（ゲームオーバー時のスコア・ハイスコア付与）"
  def build_replace_init_arg(mod, init_arg, elapsed, content) do
    game_over_scene = content.game_over_scene()

    if mod == game_over_scene do
      playing_state = get_playing_scene_state(content)
      score = Map.get(playing_state, :score, 0)

      :telemetry.execute(
        [:game, :session_end],
        %{elapsed_seconds: elapsed / 1000.0, score: score},
        %{}
      )

      GameEngine.SaveManager.save_high_score(score)
      Map.merge(init_arg || %{}, %{high_scores: GameEngine.SaveManager.load_high_scores()})
    else
      init_arg || %{}
    end
  end

  @doc "60フレームごとにフレームキャッシュ更新・ログ・スナップショット検証を行う"
  def maybe_log_and_cache(state, _mod, elapsed, content) do
    if state.room_id == :main and rem(state.frame_count, 60) == 0 do
      do_log_and_cache(state, elapsed, content)
    end
  end

  defp do_log_and_cache(state, elapsed, content) do
    playing_state = get_playing_scene_state(content)
    player_hp = Map.get(playing_state, :player_hp, 100.0)
    player_max_hp = Map.get(playing_state, :player_max_hp, 100.0)
    score = Map.get(playing_state, :score, 0)
    elapsed_s = elapsed / 1000.0

    render_type = GameEngine.SceneManager.render_type()
    hud_data = {player_hp, player_max_hp, score, elapsed_s}
    high_scores = if render_type == :game_over, do: GameEngine.SaveManager.load_high_scores(), else: nil

    enemy_count = GameEngine.NifBridge.get_enemy_count(state.world_ref)
    bullet_count = GameEngine.NifBridge.get_bullet_count(state.world_ref)
    physics_ms = GameEngine.NifBridge.get_frame_time_ms(state.world_ref)

    GameEngine.FrameCache.put(enemy_count, bullet_count, physics_ms, hud_data, render_type, high_scores)

    log_tick(content, elapsed_s, render_type, enemy_count, physics_ms, playing_state)
    maybe_snapshot_check(state, playing_state)
  end

  defp log_tick(content, elapsed_s, render_type, enemy_count, physics_ms, playing_state) do
    wave = content.wave_label(elapsed_s)
    budget_warn = if physics_ms > @tick_ms, do: " [OVER BUDGET]", else: ""
    log_exp = Map.get(playing_state, :exp, 0)
    log_level = Map.get(playing_state, :level, "-")
    weapon_info = format_weapon_info(Map.get(playing_state, :weapon_levels))
    boss_info = format_boss_info(playing_state)

    Logger.info(
      "[LOOP] #{wave} | scene=#{render_type} | enemies=#{enemy_count} | " <>
        "physics=#{Float.round(physics_ms, 2)}ms#{budget_warn} | " <>
        "lv=#{log_level} exp=#{log_exp} | weapons=[#{weapon_info}]" <> boss_info
    )

    :telemetry.execute(
      [:game, :tick],
      %{physics_ms: physics_ms, enemy_count: enemy_count},
      %{phase: render_type, wave: wave}
    )
  end

  defp format_weapon_info(nil), do: "-"
  defp format_weapon_info(weapon_levels) do
    Enum.map_join(weapon_levels, ", ", fn {w, lv} -> "#{w}:Lv#{lv}" end)
  end

  defp format_boss_info(playing_state) do
    boss_hp = Map.get(playing_state, :boss_hp)
    boss_max_hp = Map.get(playing_state, :boss_max_hp)

    if boss_hp != nil and boss_max_hp != nil and boss_max_hp > 0 do
      " | boss=#{Float.round(boss_hp / boss_max_hp * 100, 1)}%HP"
    else
      ""
    end
  end

  defp maybe_snapshot_check(state, playing_state) do
    score = Map.get(playing_state, :score, 0)
    kill_count = Map.get(playing_state, :kill_count, 0)

    {rust_score, _rust_hp, _rust_elapsed, rust_kill_count} =
      GameEngine.NifBridge.get_full_game_state(state.world_ref)

    if rust_score != score do
      Logger.warning("[SSOT CHECK] score mismatch: elixir=#{score} rust=#{rust_score} diff=#{score - rust_score}")
    end

    if rust_kill_count != kill_count do
      Logger.warning("[SSOT CHECK] kill_count mismatch: elixir=#{kill_count} rust=#{rust_kill_count}")
    end
  rescue
    e -> Logger.debug("[SSOT CHECK] snapshot check failed: #{inspect(e)}")
  end

  defp get_playing_scene_state(content) do
    GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}
  end
end
