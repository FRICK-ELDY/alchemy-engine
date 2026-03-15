defmodule Contents.GameEvents.Diagnostics do
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

  @doc "60フレームごとにフレームキャッシュ更新・ログ・スナップショット検証を行う"
  def maybe_log_and_cache(state, _scene_type, elapsed, content, runner) do
    if state.room_id == :main and rem(state.frame_count, 60) == 0 do
      do_log_and_cache(state, elapsed, content, runner)
    end
  end

  defp do_log_and_cache(state, elapsed, content, runner) do
    playing_state = get_playing_scene_state(content, runner)
    player_hp = Map.get(playing_state, :player_hp, 100.0)
    player_max_hp = Map.get(playing_state, :player_max_hp, 100.0)
    score = Map.get(playing_state, :score, 0)
    elapsed_s = elapsed / 1000.0

    # 呼び出し元（handle_frame_events_main の {:ok, ...} 経路）では runner は常に non-nil。
    # 防御的に nil 分岐を残し、万が一の場合に content.scene_render_type(playing_scene) で代替する。
    render_type =
      if runner, do: GenServer.call(runner, :render_type), else: content.scene_render_type(content.playing_scene())

    hud_data = {player_hp, player_max_hp, score, elapsed_s}

    high_scores =
      if render_type == :game_over, do: Core.SaveManager.load_high_scores(), else: nil

    nif_enemy_count = Core.NifBridge.get_enemy_count(state.world_ref)
    nif_bullet_count = Core.NifBridge.get_bullet_count(state.world_ref)
    physics_ms = Core.NifBridge.get_frame_time_ms(state.world_ref)

    # Rust ECS を使わないコンテンツ（BulletHell3D 等）は NIF が 0 を返すため、
    # Playing シーン state のリストから補完する。
    enemy_count =
      if nif_enemy_count == 0,
        do: playing_state |> Map.get(:enemies, []) |> length(),
        else: nif_enemy_count

    bullet_count =
      if nif_bullet_count == 0,
        do: playing_state |> Map.get(:bullets, []) |> length(),
        else: nif_bullet_count

    Core.FrameCache.put(
      enemy_count,
      bullet_count,
      physics_ms,
      hud_data,
      render_type,
      high_scores
    )

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
      Core.NifBridge.get_full_game_state(state.world_ref)

    if rust_score != score do
      Logger.warning(
        "[SSOT CHECK] score mismatch: elixir=#{score} rust=#{rust_score} diff=#{score - rust_score}"
      )
    end

    if rust_kill_count != kill_count do
      Logger.warning(
        "[SSOT CHECK] kill_count mismatch: elixir=#{kill_count} rust=#{rust_kill_count}"
      )
    end
  rescue
    e -> Logger.debug("[SSOT CHECK] snapshot check failed: #{inspect(e)}")
  end

  # Phase 5: runner (SceneStack) は get_scene_state(server, scene_type) を受け付ける。
  # content.playing_scene() は scene_type (例: :playing) を返すため、そのままでよい。
  defp get_playing_scene_state(content, runner) do
    if runner do
      GenServer.call(runner, {:get_scene_state, content.playing_scene()}) || %{}
    else
      %{}
    end
  end
end
