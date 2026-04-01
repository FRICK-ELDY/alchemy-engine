defmodule Contents.Events.Game.Diagnostics do
  @moduledoc false

  require Logger

  @tick_ms 16

  @doc "replace 遷移時の init_arg を構築する（ゲームオーバー時のスコア・ハイスコア付与）"
  def build_replace_init_arg(scene_type, init_arg, elapsed, content, runner) do
    game_over_scene = content.game_over_scene()

    if scene_type == game_over_scene do
      playing_state = get_playing_scene_state(content, runner)
      score = Map.get(playing_state, :score, 0)

      :telemetry.execute(
        [:game, :session_end],
        %{elapsed_seconds: elapsed / 1000.0, score: score},
        %{}
      )

      Core.SaveManager.save_high_score(score)
      Map.merge(init_arg || %{}, %{high_scores: Core.SaveManager.load_high_scores()})
    else
      init_arg || %{}
    end
  end

  @doc "60フレームごとにフレームキャッシュ更新・ログを行う（プレイ state ベース。NIF メトリクスは呼ばない）"
  def maybe_log_and_cache(state, _scene_type, elapsed, content, runner) do
    if state.room_id == :main and rem(state.frame_count, 60) == 0 do
      do_log_and_cache(state, elapsed, content, runner)
    end
  end

  defp do_log_and_cache(_state, elapsed, content, runner) do
    playing_state = get_playing_scene_state(content, runner)
    player_hp = Map.get(playing_state, :player_hp, 100.0)
    player_max_hp = Map.get(playing_state, :player_max_hp, 100.0)
    score = Map.get(playing_state, :score, 0)
    elapsed_s = elapsed / 1000.0

    render_type =
      if runner,
        do: GenServer.call(runner, :render_type),
        else: content.scene_render_type(content.playing_scene())

    hud_data = {player_hp, player_max_hp, score, elapsed_s}

    high_scores =
      if render_type == :game_over, do: Core.SaveManager.load_high_scores(), else: nil

    enemy_count = enemy_count_from_playing_state(playing_state)
    bullet_count = bullet_count_from_playing_state(playing_state)
    physics_ms = @tick_ms * 1.0

    Core.FrameCache.put(
      enemy_count,
      bullet_count,
      physics_ms,
      hud_data,
      render_type,
      high_scores
    )

    log_tick(content, elapsed_s, render_type, enemy_count, physics_ms, playing_state)
  end

  defp enemy_count_from_playing_state(ps) do
    case Map.get(ps, :enemies) do
      list when is_list(list) ->
        length(list)

      _ ->
        case Map.get(ps, :enemy_objects) do
          list when is_list(list) -> length(list)
          _ -> 0
        end
    end
  end

  defp bullet_count_from_playing_state(ps) do
    case Map.get(ps, :bullets) do
      list when is_list(list) ->
        length(list)

      _ ->
        case Map.get(ps, :bullet_objects) do
          list when is_list(list) -> length(list)
          _ -> 0
        end
    end
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

    if boss_hp != nil and boss_max_hp != nil and boss_max_hp > 0 and boss_hp >= 0 do
      " | boss=#{Float.round(boss_hp / boss_max_hp * 100, 1)}%HP"
    else
      ""
    end
  end

  defp get_playing_scene_state(content, runner) do
    if runner do
      GenServer.call(runner, {:get_scene_state, content.playing_scene()}) || %{}
    else
      %{}
    end
  end
end
