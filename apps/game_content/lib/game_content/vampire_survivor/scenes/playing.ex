defmodule GameContent.VampireSurvivor.Scenes.Playing do
  @moduledoc """
  プレイ中シーン。物理演算・スポーン・ボス/レベルアップチェックを行う。

  weapon_levels, level_up_pending, weapon_choices はこのシーンの state で管理する。
  level, exp, exp_to_next, boss_hp, boss_max_hp, boss_kind_id もこのシーンの state で管理する。
  """
  @behaviour GameEngine.SceneBehaviour

  alias GameContent.EntityParams
  alias GameContent.VampireSurvivor.BossSystem
  alias GameContent.VampireSurvivor.LevelSystem
  alias GameContent.VampireSurvivor.Scenes.BossAlert
  alias GameContent.VampireSurvivor.Scenes.GameOver
  alias GameContent.VampireSurvivor.Scenes.LevelUp
  alias GameContent.VampireSurvivor.SpawnSystem

  require Logger

  @impl GameEngine.SceneBehaviour
  def init(_init_arg) do
    {:ok,
     %{
       spawned_bosses: [],
       weapon_levels: %{magic_wand: 1},
       level_up_pending: false,
       weapon_choices: [],
       level: 1,
       exp: 0,
       exp_to_next: exp_required_for_next(1),
       boss_hp: nil,
       boss_max_hp: nil,
       boss_kind_id: nil,
       score: 0,
       kill_count: 0,
       player_hp: 100.0,
       player_max_hp: 100.0,
       # nil の場合は sync_elapsed/3 内で context.elapsed にフォールバックする
       # （init 時点では start_ms が不明なため nil で初期化）
       elapsed_ms: nil,
       # nil の場合は handle_no_boss 内で context.start_ms にフォールバックする
       # （init 時点では start_ms が不明なため nil で初期化）
       last_spawn_ms: nil
     }}
  end

  @impl GameEngine.SceneBehaviour
  def render_type, do: :playing

  @impl GameEngine.SceneBehaviour
  def update(context, state) do
    elapsed = context.elapsed
    player_hp = Map.get(state, :player_hp, 100.0)

    if player_hp <= 0.0 do
      Logger.info("[GAME OVER] Player HP reached 0 at #{div(elapsed, 1000)}s")
      {:transition, {:replace, GameOver, %{}}, state}
    else
      elapsed_sec = elapsed / 1000.0
      handle_no_death(context, state, elapsed_sec)
    end
  end

  defp handle_no_death(context, state, elapsed_sec) do
    %{spawned_bosses: spawned_bosses} = state

    case BossSystem.check_spawn(elapsed_sec, spawned_bosses) do
      {:spawn, boss_kind, boss_name} ->
        handle_boss_spawn(context, state, boss_kind, boss_name)

      :no_boss ->
        handle_no_boss(context, state)
    end
  end

  defp handle_boss_spawn(context, state, boss_kind, boss_name) do
    :telemetry.execute([:game, :boss_spawn], %{count: 1}, %{boss: boss_name})
    Logger.info("[BOSS] Alert: #{boss_name} incoming!")
    new_state = %{state | spawned_bosses: [boss_kind | state.spawned_bosses]}

    {:transition,
     {:push, BossAlert,
      %{
        boss_kind: boss_kind,
        boss_name: boss_name,
        alert_ms: context.now
      }}, new_state}
  end

  defp handle_no_boss(context, state) do
    %{
      level: level,
      exp: exp,
      exp_to_next: exp_to_next,
      level_up_pending: level_up_pending,
      weapon_choices: weapon_choices,
      weapon_levels: weapon_levels
    } = state

    if level_up_pending do
      :telemetry.execute([:game, :level_up], %{level: level, count: 1}, %{})
      handle_level_up(context, state, level, exp, exp_to_next, weapon_choices, weapon_levels)
    else
      last_spawn_ms = state.last_spawn_ms || context.start_ms

      new_last_spawn =
        SpawnSystem.maybe_spawn(context.world_ref, context.elapsed, last_spawn_ms)

      {:continue, %{state | last_spawn_ms: new_last_spawn}}
    end
  end

  defp handle_level_up(_context, state, _level, _exp, _exp_to_next, [], _weapon_levels) do
    Logger.info("[LEVEL UP] All weapons at max level - skipping weapon selection")
    {:continue, state}
  end

  defp handle_level_up(context, state, level, exp, exp_to_next, weapon_choices, weapon_levels) do
    choice_labels =
      Enum.map_join(weapon_choices, " / ", fn w ->
        lv = Map.get(weapon_levels, w, 0)
        LevelSystem.weapon_label(w, lv)
      end)

    Logger.info(
      "[LEVEL UP] Level #{level} -> #{level + 1} | " <>
        "EXP: #{exp} | to next: #{exp_to_next} | choices: #{choice_labels}"
    )

    {:transition,
     {:push, LevelUp,
      %{
        choices: weapon_choices,
        entered_ms: context.now,
        level: level
      }}, state}
  end

  # ── シーン state 更新ヘルパー（GameEvents から SceneManager 経由で呼ばれる）──

  def apply_level_up(state, choices) do
    %{state | level_up_pending: true, weapon_choices: choices}
  end

  def apply_weapon_selected(state, weapon) do
    max_lv = LevelSystem.max_weapon_level()
    new_levels = Map.update(state.weapon_levels, weapon, 1, &min(&1 + 1, max_lv))
    new_level = state.level + 1

    %{
      state
      | weapon_levels: new_levels,
        level_up_pending: false,
        weapon_choices: [],
        level: new_level
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
    max_hp = EntityParams.boss_max_hp(boss_kind)
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

  # ── weapon_slots 変換（I-2: set_weapon_slots NIF 用）──────────────

  @doc """
  weapon_levels マップを set_weapon_slots NIF に渡す [{kind_id, level}] リストに変換する。
  Elixir 側 Rule state が武器の SSoT であり、毎フレーム Rust に注入するために使用する。
  """
  def weapon_slots_for_nif(weapon_levels) do
    registry = GameEngine.Config.current().entity_registry().weapons

    weapon_levels
    |> Enum.flat_map(fn {weapon_name, level} ->
      case Map.get(registry, weapon_name) do
        nil -> []
        kind_id -> [{kind_id, level}]
      end
    end)
  end

  # ── プライベート ──────────────────────────────────────────────

  defp maybe_level_up(state) do
    required = exp_required_for_next(state.level)

    if state.exp >= required and required > 0 do
      content = GameEngine.Config.current()
      already_pending = Map.get(state, :level_up_pending, false)

      state =
        if already_pending do
          state
        else
          choices = content.generate_weapon_choices(state.weapon_levels)
          apply_level_up(state, choices)
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
