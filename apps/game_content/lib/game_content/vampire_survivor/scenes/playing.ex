defmodule GameContent.VampireSurvivor.Scenes.Playing do
  @moduledoc """
  プレイ中シーン。物理演算・スポーン・ボス/レベルアップチェックを行う。
  """
  @behaviour GameEngine.SceneBehaviour

  require Logger

  @impl GameEngine.SceneBehaviour
  def init(_init_arg), do: {:ok, %{spawned_bosses: []}}

  @impl GameEngine.SceneBehaviour
  def render_type, do: :playing

  @impl GameEngine.SceneBehaviour
  def update(context, state) do
    %{
      world_ref:     world_ref,
      now:           now,
      elapsed:       elapsed,
      last_spawn_ms: last_spawn_ms,
      weapon_levels: weapon_levels,
    } = context

    spawned_bosses = Map.get(state, :spawned_bosses, [])

    if GameEngine.is_player_dead?(world_ref) do
      Logger.info("[GAME OVER] Player HP reached 0 at #{div(elapsed, 1000)}s")
      {:transition, {:replace, GameContent.VampireSurvivor.Scenes.GameOver, %{}}, state}
    else
      elapsed_sec = elapsed / 1000.0

      case GameContent.VampireSurvivor.BossSystem.check_spawn(elapsed_sec, spawned_bosses) do
        {:spawn, boss_kind, boss_name} ->
          :telemetry.execute([:game, :boss_spawn], %{count: 1}, %{boss: boss_name})
          Logger.info("[BOSS] Alert: #{boss_name} incoming!")
          new_state = %{state | spawned_bosses: [boss_kind | spawned_bosses]}
          {:transition, {:push, GameContent.VampireSurvivor.Scenes.BossAlert, %{
            boss_kind: boss_kind,
            boss_name: boss_name,
            alert_ms:  now,
          }}, new_state}

        :no_boss ->
          {exp, level, level_up_pending, exp_to_next} =
            GameEngine.get_level_up_data(world_ref)

          if level_up_pending do
            :telemetry.execute([:game, :level_up], %{level: level, count: 1}, %{})
            choices = GameContent.VampireSurvivor.LevelSystem.generate_weapon_choices(weapon_levels)

            if choices == [] do
              Logger.info("[LEVEL UP] All weapons at max level - skipping weapon selection")
              GameEngine.skip_level_up(world_ref)
              {:continue, state}
            else
              choice_labels =
                Enum.map_join(choices, " / ", fn w ->
                  lv = Map.get(weapon_levels, w, 0)
                  GameContent.VampireSurvivor.LevelSystem.weapon_label(w, lv)
                end)

              Logger.info(
                "[LEVEL UP] Level #{level} -> #{level + 1} | " <>
                  "EXP: #{exp} | to next: #{exp_to_next} | choices: #{choice_labels}"
              )

              {:transition, {:push, GameContent.VampireSurvivor.Scenes.LevelUp, %{
                choices:    choices,
                entered_ms: now,
                level:      level,
              }}, state}
            end
          else
            new_last_spawn = GameContent.VampireSurvivor.SpawnSystem.maybe_spawn(world_ref, elapsed, last_spawn_ms)
            {:continue, state, %{context_updates: %{last_spawn_ms: new_last_spawn}}}
          end
      end
    end
  end
end
