defmodule GameContent.VampireSurvivor.Scenes.Playing do
  @moduledoc """
  プレイ中シーン。物理演算・スポーン・ボス/レベルアップチェックを行う。

  weapon_levels, level_up_pending, weapon_choices はこのシーンの state で管理する。
  level, exp, exp_to_next, boss_hp, boss_max_hp, boss_kind_id もこのシーンの state で管理する。
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
      level:            1,
      exp:              0,
      exp_to_next:      exp_required_for_next(1),
      boss_hp:          nil,
      boss_max_hp:      nil,
      boss_kind_id:     nil,
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
    } = context

    %{
      spawned_bosses:   spawned_bosses,
      weapon_levels:    weapon_levels,
      level_up_pending: level_up_pending,
      weapon_choices:   weapon_choices,
      level:            level,
      exp:              exp,
      exp_to_next:      exp_to_next,
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
    new_level = state.level + 1
    %{state |
      weapon_levels:    new_levels,
      level_up_pending: false,
      weapon_choices:   [],
      level:            new_level,
    }
  end

  def apply_level_up_skipped(state) do
    new_level = state.level + 1
    %{state | level_up_pending: false, weapon_choices: [], level: new_level}
  end

  # ── EXP・レベル管理（GameEvents から SceneManager 経由で呼ばれる）──

  def accumulate_exp(state, exp_gain) do
    new_exp = state.exp + exp_gain
    maybe_level_up(%{state | exp: new_exp})
  end

  def apply_boss_spawn(state, boss_kind) do
    max_hp = GameContent.EntityParams.boss_max_hp(boss_kind)
    %{state | boss_hp: max_hp, boss_max_hp: max_hp, boss_kind_id: boss_kind}
  end

  def apply_boss_damaged(state, damage) do
    if state.boss_hp != nil do
      new_hp = max(0.0, state.boss_hp - damage)
      %{state | boss_hp: new_hp}
    else
      state
    end
  end

  def apply_boss_defeated(state) do
    %{state | boss_hp: nil, boss_max_hp: nil, boss_kind_id: nil}
  end

  # ── プライベート ──────────────────────────────────────────────

  defp maybe_level_up(state) do
    required = exp_required_for_next(state.level)

    if state.exp >= required and required > 0 do
      rule = GameEngine.Config.current_rule()
      already_pending = Map.get(state, :level_up_pending, false)

      state =
        unless already_pending do
          choices = rule.generate_weapon_choices(state.weapon_levels)
          apply_level_up(state, choices)
        else
          state
        end

      # level はまだインクリメントしない（apply_weapon_selected / apply_level_up_skipped 時に行う）
      next_required = exp_required_for_next(state.level + 1)
      %{state | exp_to_next: max(0, next_required - state.exp)}
    else
      remaining = max(0, required - state.exp)
      %{state | exp_to_next: remaining}
    end
  end

  @exp_table [0, 10, 25, 45, 70, 100, 135, 175, 220, 270]
  defp exp_required_for_next(level) when level < 10 do
    Enum.at(@exp_table, level)
  end
  defp exp_required_for_next(level) do
    270 + (level - 9) * 50
  end
end
