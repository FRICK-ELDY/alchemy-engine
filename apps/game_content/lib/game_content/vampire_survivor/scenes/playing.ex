defmodule GameContent.VampireSurvivor.Scenes.Playing do
  @moduledoc """
  プレイ中シーン。物理演算・スポーン・ボス/レベルアップチェックを行う。

  weapon_levels, level_up_pending, weapon_choices はこのシーンの state で管理する。
  """
  @behaviour GameEngine.SceneBehaviour

  require Logger

  @impl GameEngine.SceneBehaviour
  def init(_init_arg) do
    {:ok, %{
      spawned_bosses:   [],
      weapon_levels:    %{magic_wand: 1},
      level_up_pending: false,
      weapon_choices:   [],
    }}
  end

  @impl GameEngine.SceneBehaviour
  def render_type, do: :playing

  @impl GameEngine.SceneBehaviour
  def update(context, state) do
    %{
      world_ref:     world_ref,
      now:           now,
      elapsed:       elapsed,
      last_spawn_ms: last_spawn_ms,
      player_hp:     player_hp,
      level:         level,
      exp:           exp,
      exp_to_next:   exp_to_next,
    } = context

    %{
      spawned_bosses:   spawned_bosses,
      weapon_levels:    weapon_levels,
      level_up_pending: level_up_pending,
      weapon_choices:   weapon_choices,
    } = state

    if player_hp <= 0.0 do
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
          if level_up_pending do
            :telemetry.execute([:game, :level_up], %{level: level, count: 1}, %{})

            if weapon_choices == [] do
              Logger.info("[LEVEL UP] All weapons at max level - skipping weapon selection")
              GameEngine.NifBridge.skip_level_up(world_ref)
              {:continue, state}
            else
              choice_labels =
                Enum.map_join(weapon_choices, " / ", fn w ->
                  lv = Map.get(weapon_levels, w, 0)
                  GameContent.VampireSurvivor.LevelSystem.weapon_label(w, lv)
                end)

              Logger.info(
                "[LEVEL UP] Level #{level} -> #{level + 1} | " <>
                  "EXP: #{exp} | to next: #{exp_to_next} | choices: #{choice_labels}"
              )

              {:transition, {:push, GameContent.VampireSurvivor.Scenes.LevelUp, %{
                choices:    weapon_choices,
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

  # ── シーン state 更新ヘルパー（GameEvents から SceneManager 経由で呼ばれる）──

  def apply_level_up(state, choices) do
    %{state | level_up_pending: true, weapon_choices: choices}
  end

  def apply_weapon_selected(state, weapon) do
    max_lv = GameContent.VampireSurvivor.LevelSystem.max_weapon_level()
    new_levels = Map.update(state.weapon_levels, weapon, 1, &min(&1 + 1, max_lv))
    %{state | weapon_levels: new_levels, level_up_pending: false, weapon_choices: []}
  end

  def apply_level_up_skipped(state) do
    %{state | level_up_pending: false, weapon_choices: []}
  end
end
