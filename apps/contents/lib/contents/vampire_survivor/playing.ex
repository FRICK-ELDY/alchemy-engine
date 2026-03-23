# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule Content.VampireSurvivor.Playing do
  @moduledoc """
  プレイ中シーン。物理演算・スポーン・ボス/レベルアップチェックを行う。

  weapon_levels, level_up_pending, weapon_choices はこのシーンの state で管理する。
  level, exp, exp_to_next, boss_hp, boss_max_hp, boss_kind_id もこのシーンの state で管理する。
  """
  @behaviour Contents.SceneBehaviour

  alias Content.EntityParams
  alias Content.VampireSurvivor.BossAlert
  alias Content.VampireSurvivor.GameOver
  alias Content.VampireSurvivor.LevelUp
  alias Content.VampireSurvivor.SpawnSystem

  require Logger

  @impl Contents.SceneBehaviour
  def init(init_arg) when is_map(init_arg) do
    default = default_playing_state()
    {:ok, Map.merge(default, init_arg)}
  end

  def init(_), do: init(%{})

  defp default_playing_state do
    %{
      spawned_bosses: [],
      weapon_levels: %{magic_wand: 1},
      weapon_cooldowns: %{},
      level_up_pending: false,
      weapon_choices: [],
      level: 1,
      exp: 0,
      exp_to_next: exp_required_for_next(1),
      boss_hp: nil,
      boss_max_hp: nil,
      boss_kind_id: nil,
      boss_x: nil,
      boss_y: nil,
      boss_vx: nil,
      boss_vy: nil,
      boss_invincible: false,
      boss_radius: nil,
      boss_render_kind: nil,
      boss_damage_per_sec: nil,
      score: 0,
      kill_count: 0,
      player_hp: 100.0,
      player_max_hp: 100.0,
      elapsed_ms: nil,
      last_spawn_ms: nil
    }
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
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

    case Content.VampireSurvivor.Playing.BossSystem.check_spawn(elapsed_sec, spawned_bosses) do
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
        Content.VampireSurvivor.Playing.LevelSystem.weapon_label(w, lv)
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
    max_lv = Content.VampireSurvivor.Playing.LevelSystem.max_weapon_level()
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

  @player_radius 32

  @doc """
  ボスを Elixir SSoT でスポーンする。BossAlert pop 時に呼ばれる。
  """
  def apply_boss_spawn_full(state, boss_kind_id, player_x, player_y, map_width, map_height) do
    max_hp = EntityParams.boss_max_hp(boss_kind_id)
    sp = EntityParams.boss_spawn_params(boss_kind_id)
    r = sp.radius

    center_x = player_x + @player_radius
    center_y = player_y + @player_radius
    bx = min(center_x + 600.0, map_width - r)
    by = max(r, min(center_y, map_height - r))

    %{
      state
      | boss_hp: max_hp,
        boss_max_hp: max_hp,
        boss_kind_id: boss_kind_id,
        boss_x: bx,
        boss_y: by,
        boss_vx: 0.0,
        boss_vy: 0.0,
        boss_invincible: false,
        boss_radius: r,
        boss_render_kind: sp.render_kind,
        boss_damage_per_sec: sp.damage_per_sec
    }
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
    %{
      state
      | boss_hp: nil,
        boss_max_hp: nil,
        boss_kind_id: nil,
        boss_x: nil,
        boss_y: nil,
        boss_vx: nil,
        boss_vy: nil,
        boss_invincible: false,
        boss_radius: nil,
        boss_render_kind: nil,
        boss_damage_per_sec: nil
    }
  end

  # ── weapon_slots 変換 ───────────────────────────────────────────────

  def weapon_slots_for_nif(weapon_levels, weapon_cooldowns \\ %{}) do
    registry = Core.Config.current().entity_registry().weapons
    weapon_params = Core.Config.current().weapon_params()

    weapon_levels
    |> Enum.flat_map(fn {name, lv} ->
      weapon_slot_entry(name, lv, registry, weapon_params, weapon_cooldowns)
    end)
  end

  defp weapon_slot_entry(weapon_name, level, registry, weapon_params, weapon_cooldowns) do
    case Map.get(registry, weapon_name) do
      nil ->
        []

      kind_id ->
        cooldown_timer = Map.get(weapon_cooldowns, weapon_name, 0.0)
        wp = Enum.at(weapon_params, kind_id)
        {precomputed_damage, cooldown_sec} = slot_damage_and_cooldown(wp, kind_id, level)
        [{kind_id, level, cooldown_timer, cooldown_sec, precomputed_damage}]
    end
  end

  defp slot_damage_and_cooldown(wp, _kind_id, level) when is_map(wp) do
    damage =
      Content.VampireSurvivor.Playing.WeaponFormulas.effective_damage(wp[:damage], max(1, level))

    cd =
      Content.VampireSurvivor.Playing.WeaponFormulas.effective_cooldown(
        wp[:cooldown],
        max(1, level)
      )

    {damage, cd}
  end

  defp slot_damage_and_cooldown(nil, kind_id, _level) do
    Logger.warning("weapon_slots_for_nif: kind_id=#{kind_id} not found in weapon_params")
    {0, 1.0}
  end

  # ── プライベート ──────────────────────────────────────────────

  defp maybe_level_up(state) do
    required = exp_required_for_next(state.level)

    if state.exp >= required and required > 0 do
      content = Core.Config.current()
      already_pending = Map.get(state, :level_up_pending, false)

      state =
        if already_pending do
          state
        else
          choices = content.generate_weapon_choices(state.weapon_levels)
          apply_level_up(state, choices)
        end

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

# ───────────────────────────────────────────────────────────────────
# VampireSurvivor 固有: 武器フォーミュラ（内包）
# ───────────────────────────────────────────────────────────────────

defmodule Content.VampireSurvivor.Playing.WeaponFormulas do
  @moduledoc """
  武器の数式計算ロジック。Rust の weapon.rs と同値の SSoT。
  """
  alias Content.VampireSurvivor.EntityParams

  @max_weapon_level 8

  def effective_damage(base_damage, level) when level >= 1 do
    lv = min(level, @max_weapon_level)
    inc = max(div(base_damage, 4), 1)
    base_damage + (lv - 1) * inc
  end

  def effective_cooldown(base_cooldown, level) when level >= 1 do
    lv = min(level, @max_weapon_level)
    factor = 1.0 - (lv - 1) * 0.07
    min_cooldown = base_cooldown * 0.5
    max(base_cooldown * factor, min_cooldown)
  end

  def whip_range(base_range, level) when level >= 1 do
    base_range + (level - 1) * 20.0
  end

  def aura_radius(base_range, level) when level >= 1 do
    base_range + (level - 1) * 15.0
  end

  def chain_count_for_level(base_chain_count, level) when level >= 1 do
    base_chain_count + div(level, 2)
  end

  def bullet_count(nil, _level), do: 1

  def bullet_count(bullet_table, level) when is_list(bullet_table) do
    idx = min(level, @max_weapon_level)
    Enum.at(bullet_table, idx, 1)
  end

  def weapon_upgrade_descs(weapon_choices, weapon_levels, weapon_params)
      when is_list(weapon_choices) and is_map(weapon_levels) and is_list(weapon_params) do
    registry = EntityParams.entity_registry().weapons

    Enum.map(weapon_choices, fn choice ->
      case resolve_weapon_name(choice) do
        {:ok, name} -> desc_for_weapon(registry, weapon_levels, weapon_params, name)
        :error -> ["Upgrade weapon"]
      end
    end)
  end

  defp desc_for_weapon(registry, weapon_levels, weapon_params, name) do
    kind_id = Map.get(registry, name)
    current_lv = Map.get(weapon_levels, name, 0) |> max(0)
    wp = kind_id != nil && Enum.at(weapon_params, kind_id)

    if wp, do: weapon_upgrade_desc(kind_id, current_lv, wp), else: ["Upgrade weapon"]
  end

  defp resolve_weapon_name(choice) when is_atom(choice) do
    if registered_weapon?(choice), do: {:ok, choice}, else: :error
  end

  defp resolve_weapon_name(choice) when is_binary(choice) do
    atom = String.to_existing_atom(choice)
    if registered_weapon?(atom), do: {:ok, atom}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp resolve_weapon_name(_), do: :error

  defp registered_weapon?(atom) do
    registry = EntityParams.entity_registry().weapons
    Map.has_key?(registry, atom)
  end

  defp weapon_upgrade_desc(_kind_id, current_lv, wp) do
    lv_for_current = max(1, current_lv)
    next_lv = min(current_lv + 1, @max_weapon_level)
    base = base_upgrade_lines(wp, lv_for_current, next_lv)
    fire_pattern = wp.fire_pattern |> to_string() |> String.downcase()
    fire_pattern_extra(wp, fire_pattern, current_lv, next_lv, lv_for_current, base)
  end

  defp base_upgrade_lines(wp, lv_for_current, next_lv) do
    dmg = fn lv -> effective_damage(wp.damage, max(1, lv)) end
    cd = fn lv -> effective_cooldown(wp.cooldown, max(1, lv)) end

    [
      "DMG: #{dmg.(lv_for_current)} -> #{dmg.(next_lv)}",
      "CD:  #{Float.round(cd.(lv_for_current), 1)}s -> #{Float.round(cd.(next_lv), 1)}s"
    ]
  end

  defp fire_pattern_extra(wp, "aimed", _current_lv, next_lv, lv_for_current, base) do
    bullets = fn lv -> bullet_count(wp.bullet_table, max(1, lv)) end
    bullets_now = bullets.(lv_for_current)
    bullets_next = bullets.(next_lv)

    extra =
      if bullets_next > bullets_now,
        do: ["Shots: #{bullets_now} -> #{bullets_next} (+)"],
        else: ["Shots: #{bullets_now}"]

    base ++ extra
  end

  defp fire_pattern_extra(_wp, "fixed_up", _, _, _, base), do: base ++ ["Throws upward"]

  defp fire_pattern_extra(_wp, "radial", current_lv, next_lv, _lv_for_current, base) do
    dirs_now = if current_lv == 0 or current_lv <= 3, do: 4, else: 8
    dirs_next = if next_lv <= 3, do: 4, else: 8

    extra =
      if dirs_next > dirs_now,
        do: ["Dirs: #{dirs_now} -> #{dirs_next} (+)"],
        else: ["#{dirs_now}-way fire"]

    base ++ extra
  end

  defp fire_pattern_extra(wp, "whip", _current_lv, next_lv, lv_for_current, base) do
    range_now = whip_range(wp.range, lv_for_current) |> trunc()
    range_next = whip_range(wp.range, next_lv) |> trunc()
    base ++ ["Range: #{range_now}px -> #{range_next}px", "Fan sweep (108°)"]
  end

  defp fire_pattern_extra(_wp, "piercing", _, _, _, base), do: base ++ ["Piercing shot"]

  defp fire_pattern_extra(wp, "chain", _current_lv, next_lv, lv_for_current, base) do
    chain_now = chain_count_for_level(wp.chain_count, lv_for_current)
    chain_next = chain_count_for_level(wp.chain_count, next_lv)
    base ++ ["Chain: #{chain_now} -> #{chain_next} targets"]
  end

  defp fire_pattern_extra(wp, "aura", _current_lv, next_lv, lv_for_current, base) do
    r_now = aura_radius(wp.range, lv_for_current) |> trunc()
    r_next = aura_radius(wp.range, next_lv) |> trunc()
    base ++ ["Radius: #{r_now}px -> #{r_next}px"]
  end

  defp fire_pattern_extra(_wp, _, _, _, _, base), do: base
end

# ───────────────────────────────────────────────────────────────────
# VampireSurvivor 固有: レベルシステム（内包）
# ───────────────────────────────────────────────────────────────────

defmodule Content.VampireSurvivor.Playing.LevelSystem do
  @moduledoc """
  レベルアップ・武器選択生成の純粋関数モジュール（ヴァンサバ固有）。
  """
  @all_weapons [:magic_wand, :garlic, :axe, :cross, :whip, :fireball, :lightning]
  @max_weapon_level 8
  @max_weapon_slots 6

  def max_weapon_level, do: @max_weapon_level

  def generate_weapon_choices(weapon_levels) when is_map(weapon_levels) do
    slots_full? = map_size(weapon_levels) >= @max_weapon_slots

    @all_weapons
    |> Enum.reject(fn w ->
      lv = Map.get(weapon_levels, w, 0)
      lv >= @max_weapon_level or (slots_full? and lv == 0)
    end)
    |> Enum.sort_by(fn w ->
      lv = Map.get(weapon_levels, w, 0)
      if lv == 0, do: -1, else: lv
    end)
    |> Enum.take(3)
  end

  def weapon_label(weapon, level) when is_integer(level) and level > 1 do
    "#{weapon_label(weapon)} Lv.#{level}"
  end

  def weapon_label(weapon, _level), do: weapon_label(weapon)

  def weapon_label(:magic_wand), do: "Magic Wand (auto-aim)"
  def weapon_label(:garlic), do: "Garlic (aura damage)"
  def weapon_label(:axe), do: "Axe (upward throw)"
  def weapon_label(:cross), do: "Cross (4-way fire)"
  def weapon_label(:whip), do: "Whip (fan sweep)"
  def weapon_label(:fireball), do: "Fireball (piercing)"
  def weapon_label(:lightning), do: "Lightning (chain)"
  def weapon_label(other), do: to_string(other)
end

# ───────────────────────────────────────────────────────────────────
# VampireSurvivor 固有: ボスシステム（内包）
# ───────────────────────────────────────────────────────────────────

defmodule Content.VampireSurvivor.Playing.BossSystem do
  @moduledoc """
  ボスエネミーの出現スケジュールを管理する純粋関数モジュール（ヴァンサバ固有）。
  """
  @boss_schedule [
    {180, :slime_king, "Slime King"},
    {360, :bat_lord, "Bat Lord"},
    {540, :stone_golem, "Stone Golem"}
  ]

  @boss_alert_duration_ms 3_000

  def check_spawn(elapsed_sec, spawned_bosses) when is_list(spawned_bosses) do
    @boss_schedule
    |> Enum.find(fn {trigger_sec, kind, _name} ->
      elapsed_sec >= trigger_sec and kind not in spawned_bosses
    end)
    |> case do
      {_sec, kind, name} -> {:spawn, kind, name}
      nil -> :no_boss
    end
  end

  def alert_duration_ms, do: @boss_alert_duration_ms

  def boss_label(:slime_king), do: "Slime King"
  def boss_label(:bat_lord), do: "Bat Lord"
  def boss_label(:stone_golem), do: "Stone Golem"
  def boss_label(other), do: to_string(other)
end

# ───────────────────────────────────────────────────────────────────
# VampireSurvivor 固有: レベルコンポーネント（内包）
# ───────────────────────────────────────────────────────────────────

defmodule Content.VampireSurvivor.LevelComponent do
  @moduledoc """
  レベル・EXP・スコア・プレイヤー HP・アイテムドロップ・武器選択 UI を担うコンポーネント。
  """
  @behaviour Core.Component
  require Logger

  @drop_magnet_threshold 2
  @drop_potion_threshold 7

  @item_gem Content.EntityParams.item_kind_gem()
  @item_potion Content.EntityParams.item_kind_potion()
  @item_magnet Content.EntityParams.item_kind_magnet()

  @potion_heal_value 20
  @invincible_ms 500

  @impl Core.Component
  def on_frame_event({:enemy_killed, enemy_kind, x_bits, y_bits, _}, context) do
    content = Core.Config.current()
    exp = content.enemy_exp_reward(enemy_kind)
    x = bits_to_f32(x_bits)
    y = bits_to_f32(y_bits)

    score_delta = apply_kill_to_scene(content, exp)

    call_nif(:add_score_popup, fn ->
      lifetime = Core.Config.current().score_popup_lifetime()
      Core.NifBridge.add_score_popup(context.world_ref, x, y, score_delta, lifetime)
    end)

    spawn_item_drop(context.world_ref, enemy_kind, x, y, exp)

    :ok
  end

  def on_frame_event({:player_damaged, damage_x1000, _, _, _}, context) do
    damage = damage_x1000 / 1000.0
    content = Core.Config.current()
    runner = content.flow_runner(:main)
    invincible_until_ms = context.now + @invincible_ms

    if runner do
      Contents.Scenes.Stack.update_by_scene_type(
        runner,
        content.playing_scene(),
        &apply_player_damage(&1, damage, invincible_until_ms)
      )
    end

    :ok
  end

  def on_frame_event({:item_pickup, item_kind, value, _, _}, _context)
      when item_kind == @item_potion do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      heal = value

      Contents.Scenes.Stack.update_by_scene_type(runner, content.playing_scene(), fn state ->
        max_hp = Map.get(state, :player_max_hp, 100.0)
        current_hp = Map.get(state, :player_hp, 100.0)
        new_hp = min(max_hp, current_hp + heal)
        Map.put(state, :player_hp, new_hp)
      end)
    end

    :ok
  end

  def on_frame_event({:item_pickup, _item_kind, _value, _, _}, _context), do: :ok

  def on_frame_event({:weapon_cooldown_updated, kind_id, cooldown_bits, _, _}, _context) do
    cooldown = bits_to_f32(cooldown_bits)
    content = Core.Config.current()
    runner = content.flow_runner(:main)
    weapon_name = kind_id_to_weapon_name(kind_id, content)

    if runner && weapon_name do
      Contents.Scenes.Stack.update_by_scene_type(runner, content.playing_scene(), fn state ->
        cooldowns = Map.get(state, :weapon_cooldowns, %{})
        Map.put(state, :weapon_cooldowns, Map.put(cooldowns, weapon_name, cooldown))
      end)
    end

    :ok
  end

  def on_frame_event(_event, _context), do: :ok

  defp apply_player_damage(state, damage, invincible_until_ms) do
    state
    |> Map.update(:player_hp, 100.0, fn hp -> max(0.0, hp - damage) end)
    |> Map.put(:invincible_until_ms, invincible_until_ms)
  end

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.Scenes.Stack.get_scene_state(runner, content.playing_scene())) || %{}

    inj = Process.get(:frame_injection, %{})
    inj = merge_player_snapshot(inj, playing_state, context)
    inj = merge_elapsed(inj, playing_state, context)
    inj = merge_weapon_slots(inj, content, playing_state)
    inj = merge_enemy_damage_this_frame(inj, content, context)
    Process.put(:frame_injection, inj)

    :ok
  end

  @impl Core.Component
  def on_event({:entity_removed, world_ref, kind_id, x, y}, _context) do
    roll = :rand.uniform(100)

    cond do
      roll <= @drop_magnet_threshold ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_magnet, 0)

      roll <= @drop_potion_threshold ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_potion, @potion_heal_value)

      true ->
        exp_reward = Content.EntityParams.enemy_exp_reward(kind_id)
        Core.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp_reward)
    end

    :ok
  end

  def on_event({:ui_action, "__skip__"}, context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.Scenes.Stack.get_scene_state(runner, content.playing_scene())) || %{}

    if Map.get(playing_state, :level_up_pending, false) and runner do
      Logger.info("[LEVEL UP] Skipped from renderer UI")

      Contents.Scenes.Stack.update_by_scene_type(
        runner,
        content.playing_scene(),
        &content.apply_level_up_skipped/1
      )

      close_level_up_scene_if_active(content, context, runner)
    end

    :ok
  end

  def on_event({:ui_action, weapon_name}, context) when is_binary(weapon_name) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.Scenes.Stack.get_scene_state(runner, content.playing_scene())) || %{}

    if Map.get(playing_state, :level_up_pending, false) and runner do
      weapon_levels = Map.get(playing_state, :weapon_levels, %{})
      {action, weapon} = resolve_weapon(weapon_name, weapon_levels, content)

      case action do
        :apply ->
          Logger.info("[LEVEL UP] Weapon selected from renderer: #{inspect(weapon)}")

          Contents.Scenes.Stack.update_by_scene_type(
            runner,
            content.playing_scene(),
            &content.apply_weapon_selected(&1, weapon)
          )

        :skip ->
          Contents.Scenes.Stack.update_by_scene_type(
            runner,
            content.playing_scene(),
            &content.apply_level_up_skipped/1
          )
      end

      close_level_up_scene_if_active(content, context, runner)
    end

    :ok
  end

  def on_event({:ui_action, "__auto_pop__", scene_state}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      case scene_state do
        %{choices: [first | _]} ->
          Logger.info("[LEVEL UP] Auto-selected: #{inspect(first)} -> resuming")

          Contents.Scenes.Stack.update_by_scene_type(
            runner,
            content.playing_scene(),
            &content.apply_weapon_selected(&1, first)
          )

        _ ->
          Logger.info("[LEVEL UP] Auto-skipped (no choices) -> resuming")

          Contents.Scenes.Stack.update_by_scene_type(
            runner,
            content.playing_scene(),
            &content.apply_level_up_skipped/1
          )
      end
    end

    :ok
  end

  def on_event(_event, _context), do: :ok

  defp merge_player_snapshot(inj, playing_state, context) do
    player_hp = Map.get(playing_state, :player_hp, 100.0)
    invincible_until_ms = Map.get(playing_state, :invincible_until_ms)
    now_ms = context.now

    invincible_timer =
      case invincible_until_ms do
        nil -> 0.0
        until when until > now_ms -> (until - now_ms) / 1000.0
        _ -> 0.0
      end

    Map.put(inj, :player_snapshot, {player_hp, invincible_timer})
  end

  defp merge_elapsed(inj, playing_state, context) do
    elapsed_ms =
      case Map.get(playing_state, :elapsed_ms) do
        nil -> context.elapsed
        val -> val
      end

    Map.put(inj, :elapsed_seconds, elapsed_ms / 1000.0)
  end

  defp merge_enemy_damage_this_frame(inj, content, context) do
    if function_exported?(content, :enemy_damage_this_frame, 1) do
      list = content.enemy_damage_this_frame(context)
      Map.put(inj, :enemy_damage_this_frame, list)
    else
      inj
    end
  end

  defp merge_weapon_slots(inj, content, playing_state) do
    weapon_levels = Map.get(playing_state, :weapon_levels)
    weapon_cooldowns = Map.get(playing_state, :weapon_cooldowns, %{})

    slots =
      cond do
        weapon_levels == nil ->
          nil

        function_exported?(content, :weapon_slots_for_nif, 2) ->
          content.weapon_slots_for_nif(weapon_levels, weapon_cooldowns)

        function_exported?(content, :weapon_slots_for_nif, 1) ->
          content.weapon_slots_for_nif(weapon_levels)
          |> Enum.map(fn {k, l} -> {k, l, 0.0, 1.0, 0} end)

        true ->
          nil
      end

    if slots do
      Map.put(inj, :weapon_slots, slots)
    else
      inj
    end
  end

  defp kind_id_to_weapon_name(kind_id, content) do
    registry = content.entity_registry().weapons

    registry
    |> Enum.find_value(fn {name, id} -> if id == kind_id, do: name end)
  end

  defp apply_kill_to_scene(content, exp) do
    score_delta = content.score_from_exp(exp)
    runner = content.flow_runner(:main)

    if runner do
      Contents.Scenes.Stack.update_by_scene_type(runner, content.playing_scene(), fn state ->
        state
        |> Map.update(:score, score_delta, &(&1 + score_delta))
        |> Map.update(:kill_count, 1, &(&1 + 1))
        |> Content.VampireSurvivor.Helpers.maybe_accumulate_exp(content, exp)
      end)
    end

    score_delta
  end

  defp spawn_item_drop(world_ref, _enemy_kind, x, y, exp) do
    roll = :rand.uniform(100)

    cond do
      roll <= @drop_magnet_threshold ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_magnet, 0)

      roll <= @drop_potion_threshold ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_potion, @potion_heal_value)

      true ->
        Core.NifBridge.spawn_item(world_ref, x, y, @item_gem, exp)
    end
  end

  defp bits_to_f32(bits) do
    <<f::float-size(32)>> = <<bits::unsigned-size(32)>>
    f
  end

  defp resolve_weapon(weapon_name, weapon_levels, content) do
    requested =
      try do
        String.to_existing_atom(weapon_name)
      rescue
        ArgumentError -> nil
      end

    weapons_registry = content.entity_registry().weapons
    allowed = weapons_registry |> Map.keys() |> MapSet.new()
    fallback = Map.keys(weapon_levels) |> List.first() || :magic_wand

    cond do
      is_atom(requested) and MapSet.member?(allowed, requested) ->
        {:apply, requested}

      MapSet.member?(allowed, fallback) ->
        Logger.warning(
          "[LEVEL UP] Renderer weapon '#{weapon_name}' not available. Falling back to #{inspect(fallback)}."
        )

        {:apply, fallback}

      true ->
        Logger.warning(
          "[LEVEL UP] Renderer weapon '#{weapon_name}' not available and no valid fallback. Skipping."
        )

        {:skip, :__skip__}
    end
  end

  defp close_level_up_scene_if_active(content, context, runner) do
    if function_exported?(content, :level_up_scene, 0) and runner do
      level_up_scene = content.level_up_scene()

      case Contents.Scenes.Stack.current(runner) do
        {:ok, %{scene_type: ^level_up_scene}} ->
          context.pop_scene.()

        _ ->
          :ok
      end
    end
  end

  defp call_nif(name, fun) do
    case fun.() do
      {:error, reason} ->
        Logger.error("[NIF ERROR] #{name} failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end
end

# ───────────────────────────────────────────────────────────────────
# VampireSurvivor 固有: ボスコンポーネント（内包）
# ───────────────────────────────────────────────────────────────────

defmodule Content.VampireSurvivor.BossComponent do
  @moduledoc """
  ボスAI制御・ボス HP 管理・ボスフレームイベント処理を担うコンポーネント。
  """
  @behaviour Core.Component

  require Logger

  @item_gem Content.EntityParams.item_kind_gem()
  @boss_slime_king Content.EntityParams.boss_kind_slime_king()
  @boss_bat_lord Content.EntityParams.boss_kind_bat_lord()
  @boss_stone_golem Content.EntityParams.boss_kind_stone_golem()
  @map_width 4096.0
  @map_height 4096.0

  @impl Core.Component
  def on_frame_event({:boss_damaged, damage_x1000, _, _, _}, context) do
    damage = damage_x1000 / 1000.0
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      playing_scene = content.playing_scene()

      Contents.Scenes.Stack.update_by_scene_type(
        runner,
        playing_scene,
        &apply_boss_damage(&1, damage, context)
      )
    end

    :ok
  end

  def on_frame_event(_event, _context), do: :ok

  defp apply_boss_damage(state, _damage, _context) when state.boss_hp == nil, do: state

  defp apply_boss_damage(state, damage, context) do
    new_hp = max(0.0, state.boss_hp - damage)
    state = %{state | boss_hp: new_hp}

    if new_hp <= 0.0 do
      apply_defeated(state, context)
    else
      state
    end
  end

  defp apply_defeated(state, context) do
    content = Core.Config.current()
    boss_kind = state.boss_kind_id
    exp = content.boss_exp_reward(boss_kind)
    score_delta = content.score_from_exp(exp)
    x = state.boss_x || 0.0
    y = state.boss_y || 0.0

    drop_boss_gems(context.world_ref, x, y, exp)
    Process.delete({__MODULE__, :boss_phase_timer})

    new_state =
      state
      |> Map.update(:score, score_delta, &(&1 + score_delta))
      |> Map.update(:kill_count, 1, &(&1 + 1))
      |> Content.VampireSurvivor.Helpers.maybe_accumulate_exp(content, exp)
      |> Content.VampireSurvivor.Helpers.maybe_apply_boss_defeated(content)

    new_state
  end

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner && Contents.Scenes.Stack.get_scene_state(runner, content.playing_scene())) || %{}

    snapshot = build_snapshot(playing_state, context)
    inj = Process.get(:frame_injection, %{})
    Process.put(:frame_injection, Map.put(inj, :special_entity_snapshot, snapshot))

    :ok
  end

  defp build_snapshot(%{boss_kind_id: nil}, _context), do: :none
  defp build_snapshot(%{boss_hp: nil}, _context), do: :none
  defp build_snapshot(%{boss_hp: hp}, _context) when hp <= 0, do: :none

  defp build_snapshot(state, context) do
    x = state.boss_x || 0.0
    y = state.boss_y || 0.0
    radius = state.boss_radius || 48.0
    damage_per_sec = state.boss_damage_per_sec || 30.0
    inv = Map.get(state, :boss_invincible, false)
    dt = Map.get(context, :dt, 16 / 1000.0)
    damage_this_frame = damage_per_sec * dt
    {:alive, x, y, radius, damage_this_frame, inv}
  end

  @impl Core.Component
  def on_physics_process(context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    playing_state =
      (runner &&
         Contents.Scenes.Stack.get_scene_state(runner, content.playing_scene())) ||
        %{}

    kind_id = Map.get(playing_state, :boss_kind_id)

    if kind_id != nil do
      update_boss_ai(context, playing_state, kind_id)
    end

    :ok
  end

  @impl Core.Component
  def on_event(_event, _context), do: :ok

  @impl Core.Component
  def on_engine_message({:boss_dash_end, _world_ref}, _context) do
    content = Core.Config.current()
    runner = content.flow_runner(:main)

    if runner do
      Contents.Scenes.Stack.update_by_scene_type(
        runner,
        content.playing_scene(),
        &clear_boss_dash_state/1
      )
    end

    :ok
  end

  def on_engine_message(_msg, _context), do: :ok

  defp clear_boss_dash_state(%{boss_kind_id: nil} = state), do: state

  defp clear_boss_dash_state(state),
    do: %{state | boss_invincible: false, boss_vx: 0.0, boss_vy: 0.0}

  defp drop_boss_gems(world_ref, x, y, exp_reward) do
    gem_value = div(exp_reward, 10)

    for _ <- 1..10 do
      ox = (:rand.uniform() - 0.5) * 200.0
      oy = (:rand.uniform() - 0.5) * 200.0
      Core.NifBridge.spawn_item(world_ref, x + ox, y + oy, @item_gem, gem_value)
    end
  end

  defp update_boss_ai(context, state, kind_id) do
    world_ref = context.world_ref
    dt = context.tick_ms / 1000.0
    {px, py} = Core.NifBridge.get_player_pos(world_ref)
    bp = Content.EntityParams.boss_params_by_id(kind_id)

    bx = state.boss_x || px
    by = state.boss_y || py

    {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)

    phase_timer = Process.get({__MODULE__, :boss_phase_timer}, bp.special_interval)
    new_timer = phase_timer - dt

    {final_vx, final_vy, new_state} =
      if new_timer <= 0.0 do
        handle_boss_special_action(world_ref, kind_id, px, py, bx, by, bp)
      else
        Process.put({__MODULE__, :boss_phase_timer}, new_timer)
        {vx, vy, nil}
      end

    runner = Core.Config.current().flow_runner(:main)
    playing_scene = Core.Config.current().playing_scene()
    mv = {final_vx || vx, final_vy || vy}

    if runner do
      Contents.Scenes.Stack.update_by_scene_type(
        runner,
        playing_scene,
        &apply_boss_position_update(&1, mv, dt, new_state)
      )
    end
  end

  defp apply_boss_position_update(s, {vel_x, vel_y}, dt, new_state) do
    new_x = (s.boss_x || 0) + vel_x * dt
    new_y = (s.boss_y || 0) + vel_y * dt
    r = s.boss_radius || 48.0
    clamped_x = clamp(new_x, r, @map_width - r)
    clamped_y = clamp(new_y, r, @map_height - r)

    s
    |> Map.put(:boss_x, clamped_x)
    |> Map.put(:boss_y, clamped_y)
    |> Map.put(:boss_vx, vel_x)
    |> Map.put(:boss_vy, vel_y)
    |> maybe_apply_special_state(new_state)
  end

  defp maybe_apply_special_state(state, nil), do: state

  defp maybe_apply_special_state(state, %{invincible: true, vx: vx, vy: vy}) do
    %{state | boss_invincible: true, boss_vx: vx, boss_vy: vy}
  end

  defp maybe_apply_special_state(state, _), do: state

  defp handle_boss_special_action(world_ref, @boss_slime_king, px, py, bx, by, bp) do
    spawn_slimes_around(world_ref, bx, by)
    Process.put({__MODULE__, :boss_phase_timer}, bp.special_interval)
    {vx, vy} = chase_velocity(px, py, bx, by, bp.speed)
    {vx, vy, nil}
  end

  defp handle_boss_special_action(_world_ref, @boss_bat_lord, px, py, bx, by, bp) do
    {dvx, dvy} = chase_velocity(px, py, bx, by, bp.dash_speed)
    Process.put({__MODULE__, :boss_phase_timer}, bp.special_interval)

    Process.send_after(self(), {:boss_dash_end, nil}, bp.dash_duration_ms)
    {dvx, dvy, %{invincible: true, vx: dvx, vy: dvy}}
  end

  defp handle_boss_special_action(world_ref, @boss_stone_golem, px, py, boss_x, boss_y, bp) do
    for {dx, dy} <- [{1.0, 0.0}, {-1.0, 0.0}, {0.0, 1.0}, {0.0, -1.0}] do
      Core.NifBridge.spawn_projectile(
        world_ref,
        boss_x,
        boss_y,
        dx * bp.projectile_speed,
        dy * bp.projectile_speed,
        bp.projectile_damage,
        bp.projectile_lifetime,
        14
      )
    end

    Process.put({__MODULE__, :boss_phase_timer}, bp.special_interval)
    {vx, vy} = chase_velocity(px, py, boss_x, boss_y, bp.speed)
    {vx, vy, nil}
  end

  defp handle_boss_special_action(_world_ref, _kind_id, _px, _py, _bx, _by, bp) do
    Process.put({__MODULE__, :boss_phase_timer}, bp.special_interval)
    {0.0, 0.0, nil}
  end

  defp chase_velocity(px, py, bx, by, speed) do
    ddx = px - bx
    ddy = py - by
    dist = :math.sqrt(ddx * ddx + ddy * ddy)

    if dist < 0.001 do
      {0.0, 0.0}
    else
      {ddx / dist * speed, ddy / dist * speed}
    end
  end

  defp spawn_slimes_around(world_ref, bx, by) do
    positions =
      for i <- 0..7 do
        angle = i * :math.pi() * 2.0 / 8.0
        {bx + :math.cos(angle) * 120.0, by + :math.sin(angle) * 120.0}
      end

    Core.NifBridge.spawn_enemies_at(
      world_ref,
      Content.EntityParams.enemy_kind_slime(),
      positions
    )
  end

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _, _), do: v
end
