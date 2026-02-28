defmodule GameEngine.GameEvents do
  @moduledoc """
  Rust からの frame_events を受信し、フェーズ管理・NIF 呼び出しを行う GenServer。

  Rust 側が高精度 60 Hz でゲームループを駆動し、
  Elixir は `{:frame_events, events}` を受信してイベント駆動でシーン制御を行う。

  ## Elixir as SSoT 移行状況
  - フェーズ1完了: score, kill_count, elapsed_ms を Elixir 側で管理
  - フェーズ2完了: player_hp, player_max_hp を Elixir 側で管理
  - フェーズ3完了: level, exp, exp_to_next を Elixir 側で管理
               weapon_levels, level_up_pending, weapon_choices は Playing シーン state で管理
  - フェーズ4完了: boss_hp, boss_max_hp, boss_kind_id を Elixir 側で管理
  - フェーズ5完了: render_started フラグを Elixir 側で管理、UI アクションを直接受信
  """

  use GenServer
  require Logger

  @tick_ms 16

  def start_link(opts \\ []) do
    room_id = Keyword.get(opts, :room_id, :main)
    name = process_name(room_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  defp process_name(:main), do: __MODULE__
  defp process_name(room_id), do: {:via, Registry, {GameEngine.RoomRegistry, room_id}}

  def save_session, do: GenServer.cast(__MODULE__, :save_session)

  def load_session, do: GenServer.call(__MODULE__, :load_session, 5_000)

  @impl true
  def init(opts) do
    room_id = Keyword.get(opts, :room_id, :main)

    if room_id == :main do
      GameEngine.RoomRegistry.register(:main)
    end

    world_ref = GameEngine.NifBridge.create_world()

    # Phase 3-A: WorldBehaviour が setup_world_params/1 を実装していれば呼び出す
    world = GameEngine.Config.current_world()
    if function_exported?(world, :setup_world_params, 1) do
      world.setup_world_params(world_ref)
    end

    map_id = Application.get_env(:game_server, :map, :plain)
    obstacles = GameEngine.MapLoader.obstacles_for_map(map_id)
    GameEngine.NifBridge.set_map_obstacles(world_ref, obstacles)

    control_ref = GameEngine.NifBridge.create_game_loop_control()
    if room_id == :main, do: GameEngine.FrameCache.init()
    start_ms = now_ms()

    GameEngine.NifBridge.start_rust_game_loop(world_ref, control_ref, self())

    # フェーズ5: render_started フラグで重複起動を防止（RENDER_THREAD_RUNNING static 廃止）
    # self() を渡して描画スレッドが直接 GameEvents プロセスに送信できるようにする
    render_started =
      if room_id == :main do
        GameEngine.NifBridge.start_render_thread(world_ref, self())
        true
      else
        false
      end

    {:ok, %{
      room_id:          room_id,
      world_ref:        world_ref,
      control_ref:      control_ref,
      last_tick:        start_ms,
      frame_count:      0,
      start_ms:         start_ms,
      last_spawn_ms:    start_ms,
      # フェーズ1: スコア・統計を Elixir 側で管理
      score:            0,
      kill_count:       0,
      elapsed_ms:       0,
      # フェーズ2: プレイヤー HP を Elixir 側で管理
      player_hp:        100.0,
      player_max_hp:    100.0,
      # フェーズ3: レベル・EXP を Elixir 側で管理
      level:            1,
      exp:              0,
      exp_to_next:      exp_required_for_next(1),
      # フェーズ4: ボス状態を Elixir 側で管理
      boss_hp:          nil,
      boss_max_hp:      nil,
      boss_kind_id:     nil,
      # フェーズ5: 描画スレッド起動済みフラグ
      render_started:   render_started,
    }}
  end

  @impl true
  def terminate(_reason, %{room_id: :main}) do
    GameEngine.RoomRegistry.unregister(:main)
    :ok
  end
  def terminate(_reason, _state), do: :ok

  # ── キャスト: 武器選択 ─────────────────────────────────────────────

  @impl true
  def handle_cast({:select_weapon, :__skip__}, state) do
    rule = current_rule()
    level_up_scene = rule.level_up_scene()

    case GameEngine.SceneManager.current() do
      {:ok, %{module: ^level_up_scene}} ->
        GameEngine.NifBridge.skip_level_up(state.world_ref)
        Logger.info("[LEVEL UP] Skipped weapon selection -> resuming")
        GameEngine.NifBridge.resume_physics(state.control_ref)
        GameEngine.SceneManager.pop_scene()
        update_playing_scene_state(rule, &rule.apply_level_up_skipped/1)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:select_weapon, weapon}, state) do
    rule = current_rule()
    world = current_world()
    level_up_scene = rule.level_up_scene()

    case GameEngine.SceneManager.current() do
      {:ok, %{module: ^level_up_scene}} ->
        weapon_id = world.entity_registry().weapons[weapon] ||
                      raise "Unknown weapon: #{inspect(weapon)}"
        GameEngine.NifBridge.add_weapon(state.world_ref, weapon_id)
        Logger.info("[LEVEL UP] Weapon selected: #{inspect(weapon)} -> resuming")
        GameEngine.NifBridge.resume_physics(state.control_ref)
        GameEngine.SceneManager.pop_scene()
        update_playing_scene_state(rule, &rule.apply_weapon_selected(&1, weapon))
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast(:save_session, state) do
    case GameEngine.SaveManager.save_session(state.world_ref) do
      :ok -> Logger.info("[SAVE] Session saved")
      {:error, reason} -> Logger.warning("[SAVE] Failed: #{inspect(reason)}")
    end
    {:noreply, state}
  end

  # ── コール: セッションロード ────────────────────────────────────────

  @impl true
  def handle_call(:load_session, _from, state) do
    rule = current_rule()
    result = GameEngine.SaveManager.load_session(state.world_ref)

    case result do
      :ok ->
        GameEngine.SceneManager.replace_scene(rule.physics_scenes() |> List.first(), %{})
        new_state = reset_elixir_state(state)
        {:reply, :ok, new_state}

      other ->
        {:reply, other, state}
    end
  end

  # ── インフォ: UI アクション（フェーズ5: 描画スレッドから直接受信）──

  @impl true
  def handle_info({:ui_action, action}, state) when is_binary(action) do
    new_state =
      case action do
        "__skip__" -> handle_ui_action_skip(state)
        "__save__" ->
          GenServer.cast(self(), :save_session)
          state
        "__load__" -> handle_ui_action_load(state)
        "__load_confirm__" -> handle_ui_action_load_confirm(state)
        "__load_cancel__" -> state
        "__start__" -> state
        "__retry__" -> state
        weapon when is_binary(weapon) -> handle_ui_action_weapon(state, weapon)
      end
    {:noreply, new_state}
  end

  # ── インフォ: 移動入力（フェーズ5: 描画スレッドから直接受信）────────

  def handle_info({:move_input, dx, dy}, state) do
    GameEngine.NifBridge.set_player_input(state.world_ref, dx * 1.0, dy * 1.0)
    {:noreply, state}
  end

  # ── インフォ: フレームイベント ────────────────────────────────────

  def handle_info({:frame_events, events}, state) do
    if state.room_id != :main do
      {:noreply, %{state | last_tick: now_ms(), frame_count: state.frame_count + 1}}
    else
      handle_frame_events_main(events, state)
    end
  end

  # ── UI アクションハンドラ ─────────────────────────────────────────

  defp handle_ui_action_skip(state) do
    rule = current_rule()
    playing_state = get_playing_scene_state(rule)
    is_level_up_pending = Map.get(playing_state, :level_up_pending, false)

    if is_level_up_pending do
      GameEngine.NifBridge.skip_level_up(state.world_ref)
      Logger.info("[LEVEL UP] Skipped from renderer UI")
      update_playing_scene_state(rule, &rule.apply_level_up_skipped/1)
      maybe_close_level_up_scene(state)
    else
      state
    end
  end

  defp handle_ui_action_weapon(state, weapon_name) do
    rule = current_rule()
    world = current_world()
    playing_state = get_playing_scene_state(rule)
    is_level_up_pending = Map.get(playing_state, :level_up_pending, false)
    current_weapon_levels = Map.get(playing_state, :weapon_levels, %{})

    if is_level_up_pending do
      selected_weapon = resolve_weapon_from_name(weapon_name, current_weapon_levels, rule, world, state.world_ref)
      if selected_weapon != :__skip__ do
        Logger.info("[LEVEL UP] Weapon selected from renderer: #{inspect(selected_weapon)}")
      end
      maybe_close_level_up_scene(state)
    else
      state
    end
  end

  defp resolve_weapon_from_name(weapon_name, weapon_levels, rule, world, world_ref) when is_binary(weapon_name) do
    requested_weapon =
      try do
        String.to_existing_atom(weapon_name)
      rescue
        ArgumentError -> nil
      end

    weapons_registry = world.entity_registry().weapons
    allowed_weapons = weapons_registry |> Map.keys() |> MapSet.new()
    fallback_weapon = Map.keys(weapon_levels) |> List.first() || :magic_wand

    cond do
      is_atom(requested_weapon) and MapSet.member?(allowed_weapons, requested_weapon) ->
        GameEngine.NifBridge.add_weapon(world_ref, weapons_registry[requested_weapon])
        update_playing_scene_state(rule, &rule.apply_weapon_selected(&1, requested_weapon))
        requested_weapon

      MapSet.member?(allowed_weapons, fallback_weapon) ->
        Logger.warning("[LEVEL UP] Renderer weapon '#{weapon_name}' not available. Falling back to #{inspect(fallback_weapon)}.")
        GameEngine.NifBridge.add_weapon(world_ref, weapons_registry[fallback_weapon])
        update_playing_scene_state(rule, &rule.apply_weapon_selected(&1, fallback_weapon))
        fallback_weapon

      true ->
        Logger.warning("[LEVEL UP] Renderer weapon '#{weapon_name}' not available and no valid fallback. Skipping.")
        GameEngine.NifBridge.skip_level_up(world_ref)
        update_playing_scene_state(rule, &rule.apply_level_up_skipped/1)
        :__skip__
    end
  end

  defp handle_ui_action_load(state) do
    if GameEngine.SaveManager.has_save?() do
      do_load_session(state)
    else
      Logger.info("[LOAD] No save file")
      state
    end
  end

  defp handle_ui_action_load_confirm(state), do: do_load_session(state)

  defp do_load_session(state) do
    case GameEngine.SaveManager.load_session(state.world_ref) do
      :ok ->
        rule = current_rule()
        GameEngine.SceneManager.replace_scene(rule.physics_scenes() |> List.first(), %{})
        reset_elixir_state(state)

      :no_save ->
        Logger.info("[LOAD] No save data")
        state

      {:error, reason} ->
        Logger.warning("[LOAD] Failed: #{inspect(reason)}")
        state
    end
  end

  defp maybe_close_level_up_scene(state) do
    level_up_scene = current_rule().level_up_scene()

    case GameEngine.SceneManager.current() do
      {:ok, %{module: ^level_up_scene}} ->
        GameEngine.NifBridge.resume_physics(state.control_ref)
        GameEngine.SceneManager.pop_scene()
        state

      _ ->
        state
    end
  end

  # ── メインフレームループ ──────────────────────────────────────────

  defp handle_frame_events_main(events, state) do
    now = now_ms()
    elapsed = now - state.start_ms

    rule = current_rule()
    physics_scenes = rule.physics_scenes()

    case GameEngine.SceneManager.current() do
      :empty ->
        {:noreply, %{state | last_tick: now}}

      {:ok, %{module: mod, state: scene_state}} ->
        delta_ms = now - state.last_tick
        state = %{state | elapsed_ms: state.elapsed_ms + delta_ms}

        state = apply_frame_events(events, state)

        GameEngine.NifBridge.set_hud_state(state.world_ref, state.score, state.kill_count)
        GameEngine.NifBridge.set_player_hp(state.world_ref, state.player_hp)
        GameEngine.NifBridge.set_player_level(state.world_ref, state.level, state.exp)
        GameEngine.NifBridge.set_elapsed_seconds(state.world_ref, state.elapsed_ms / 1000.0)

        if state.boss_hp != nil do
          GameEngine.NifBridge.set_boss_hp(state.world_ref, state.boss_hp)
        end

        state = maybe_set_input_and_broadcast(state, mod, physics_scenes, events)

        context = build_context(state, now, elapsed)
        result = mod.update(context, scene_state)

        {new_scene_state, opts} = extract_state_and_opts(result)
        GameEngine.SceneManager.update_current(fn _ -> new_scene_state end)

        state = apply_context_updates(state, opts)
        state = process_transition(result, state, now, rule, current_world())
        state = maybe_log_and_cache(state, mod, elapsed, rule)

        {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}
    end
  end

  # ── フレームイベント処理（Elixir 側 SSoT 更新）──────────────────────

  defp apply_frame_events(events, state) do
    Enum.reduce(events, state, &apply_event/2)
  end

  # フェーズ1: EnemyKilled でスコア・kill_count を Elixir 側で積算
  defp apply_event({:enemy_killed, enemy_kind, _weapon_kind}, state) do
    exp = GameContent.EntityParams.enemy_exp_reward(enemy_kind)
    score_delta = GameContent.EntityParams.score_from_exp(exp)
    state
    |> Map.update!(:score, &(&1 + score_delta))
    |> Map.update!(:kill_count, &(&1 + 1))
    |> accumulate_exp(exp)
  end

  # フェーズ1: BossDefeated でスコア・kill_count を Elixir 側で積算
  defp apply_event({:boss_defeated, boss_kind, _}, state) do
    exp = GameContent.EntityParams.boss_exp_reward(boss_kind)
    score_delta = GameContent.EntityParams.score_from_exp(exp)
    state
    |> Map.update!(:score, &(&1 + score_delta))
    |> Map.update!(:kill_count, &(&1 + 1))
    |> accumulate_exp(exp)
    |> Map.merge(%{boss_hp: nil, boss_max_hp: nil, boss_kind_id: nil})
  end

  # フェーズ2: PlayerDamaged で Elixir 側 HP を減算
  defp apply_event({:player_damaged, damage_x1000, _}, state) do
    damage = damage_x1000 / 1000.0
    new_hp = max(0.0, state.player_hp - damage)
    %{state | player_hp: new_hp}
  end

  # フェーズ4: BossSpawn でボス状態を Elixir 側に設定
  defp apply_event({:boss_spawn, boss_kind, _}, state) do
    max_hp = GameContent.EntityParams.boss_max_hp(boss_kind)
    %{state | boss_hp: max_hp, boss_max_hp: max_hp, boss_kind_id: boss_kind}
  end

  # フェーズ4: BossDamaged でボス HP を Elixir 側で減算
  defp apply_event({:boss_damaged, damage_x1000, _}, state) do
    if state.boss_hp != nil do
      damage = damage_x1000 / 1000.0
      new_hp = max(0.0, state.boss_hp - damage)
      %{state | boss_hp: new_hp}
    else
      state
    end
  end

  # その他のイベント（LevelUp は Elixir 側で検知するため無視）
  defp apply_event({:level_up_event, _new_level, _}, state), do: state
  defp apply_event({:item_pickup, _item_kind, _}, state), do: state
  defp apply_event(_, state), do: state

  # フェーズ3: EXP 積算とレベルアップ検知
  defp accumulate_exp(state, exp) do
    new_exp = state.exp + exp
    maybe_level_up(%{state | exp: new_exp})
  end

  defp maybe_level_up(state) do
    required = exp_required_for_next(state.level)

    if state.exp >= required and required > 0 do
      rule = current_rule()
      playing_state = get_playing_scene_state(rule)
      already_pending = Map.get(playing_state, :level_up_pending, false)

      unless already_pending do
        weapon_levels = Map.get(playing_state, :weapon_levels, %{})
        choices = rule.generate_weapon_choices(weapon_levels)
        update_playing_scene_state(rule, &rule.apply_level_up(&1, choices))
      end

      %{state | exp_to_next: exp_required_for_next(state.level + 1) - state.exp}
    else
      remaining = max(0, exp_required_for_next(state.level) - state.exp)
      %{state | exp_to_next: remaining}
    end
  end

  # ── 入力・ブロードキャスト ────────────────────────────────────────

  defp maybe_set_input_and_broadcast(state, mod, physics_scenes, events) do
    if mod in physics_scenes do
      if state.room_id != :main do
        {dx, dy} = GameEngine.InputHandler.get_move_vector()
        GameEngine.NifBridge.set_player_input(state.world_ref, dx * 1.0, dy * 1.0)
      end
      unless events == [], do: GameEngine.EventBus.broadcast(events)
    end
    state
  end

  # ── コンテキスト構築 ──────────────────────────────────────────────

  defp build_context(state, now, elapsed) do
    base = %{
      tick_ms:       @tick_ms,
      world_ref:     state.world_ref,
      now:           now,
      elapsed:       elapsed,
      last_spawn_ms: state.last_spawn_ms,
      frame_count:   state.frame_count,
      start_ms:      state.start_ms,
      # フェーズ1〜4: Elixir 側の権威ある値をコンテキストに含める
      score:         state.score,
      kill_count:    state.kill_count,
      elapsed_ms:    state.elapsed_ms,
      player_hp:     state.player_hp,
      player_max_hp: state.player_max_hp,
      level:         state.level,
      exp:           state.exp,
      exp_to_next:   state.exp_to_next,
      boss_hp:       state.boss_hp,
      boss_max_hp:   state.boss_max_hp,
      boss_kind_id:  state.boss_kind_id,
    }
    Map.merge(current_rule().context_defaults(), base)
  end

  defp extract_state_and_opts({:continue, scene_state}), do: {scene_state, %{}}
  defp extract_state_and_opts({:continue, scene_state, opts}), do: {scene_state, opts || %{}}
  defp extract_state_and_opts({:transition, _action, scene_state}), do: {scene_state, %{}}
  defp extract_state_and_opts({:transition, _action, scene_state, opts}), do: {scene_state, opts || %{}}

  defp apply_context_updates(state, %{context_updates: updates}) when is_map(updates) do
    Map.merge(state, updates)
  end
  defp apply_context_updates(state, _), do: state

  # ── シーン遷移処理 ────────────────────────────────────────────────

  defp process_transition({:continue, _}, state, _now, _rule, _world), do: state
  defp process_transition({:continue, _, _}, state, _now, _rule, _world), do: state

  defp process_transition({:transition, :pop, scene_state}, state, _now, rule, world) do
    auto_select = Map.get(scene_state, :auto_select, false)

    if auto_select do
      case scene_state do
        %{choices: [first | _]} ->
          weapon_id = world.entity_registry().weapons[first] ||
                        raise "Unknown weapon: #{inspect(first)}"
          GameEngine.NifBridge.add_weapon(state.world_ref, weapon_id)
          Logger.info("[LEVEL UP] Auto-selected: #{inspect(first)} -> resuming")
          update_playing_scene_state(rule, &rule.apply_weapon_selected(&1, first))
        _ ->
          GameEngine.NifBridge.skip_level_up(state.world_ref)
          Logger.info("[LEVEL UP] Auto-skipped (no choices) -> resuming")
          update_playing_scene_state(rule, &rule.apply_level_up_skipped/1)
      end
      GameEngine.NifBridge.resume_physics(state.control_ref)
      GameEngine.SceneManager.pop_scene()
      state
    else
      GameEngine.NifBridge.resume_physics(state.control_ref)
      GameEngine.SceneManager.pop_scene()
      state
    end
  end

  defp process_transition({:transition, {:push, mod, init_arg}, _}, state, _now, rule, _world) do
    if mod == rule.level_up_scene() or mod == rule.boss_alert_scene() do
      GameEngine.NifBridge.pause_physics(state.control_ref)
    end
    GameEngine.SceneManager.push_scene(mod, init_arg)
    state
  end

  defp process_transition({:transition, {:replace, mod, init_arg}, _}, state, _now, rule, _world) do
    game_over_scene = rule.game_over_scene()

    init_arg =
      if mod == game_over_scene do
        :telemetry.execute(
          [:game, :session_end],
          %{elapsed_seconds: state.elapsed_ms / 1000.0, score: state.score},
          %{}
        )

        GameEngine.SaveManager.save_high_score(state.score)
        Map.merge(init_arg || %{}, %{high_scores: GameEngine.SaveManager.load_high_scores()})
      else
        init_arg || %{}
      end

    GameEngine.SceneManager.replace_scene(mod, init_arg)
    state
  end

  defp process_transition(_, state, _, _, _), do: state

  # ── ログ・キャッシュ更新 ──────────────────────────────────────────

  defp maybe_log_and_cache(state, _mod, _elapsed, rule) do
    if state.room_id == :main and rem(state.frame_count, 60) == 0 do
      elapsed_s = state.elapsed_ms / 1000.0

      hud_data = {state.player_hp, state.player_max_hp, state.score, elapsed_s}
      render_type = GameEngine.SceneManager.render_type()
      high_scores = if render_type == :game_over, do: GameEngine.SaveManager.load_high_scores(), else: nil

      enemy_count = GameEngine.NifBridge.get_enemy_count(state.world_ref)
      bullet_count = GameEngine.NifBridge.get_bullet_count(state.world_ref)
      physics_ms = GameEngine.NifBridge.get_frame_time_ms(state.world_ref)

      GameEngine.FrameCache.put(enemy_count, bullet_count, physics_ms, hud_data, render_type, high_scores)

      wave = rule.wave_label(elapsed_s)
      budget_warn = if physics_ms > @tick_ms, do: " [OVER BUDGET]", else: ""

      weapon_info =
        get_playing_scene_weapon_levels(rule)
        |> Enum.map_join(", ", fn {w, lv} -> "#{w}:Lv#{lv}" end)

      boss_info =
        if state.boss_hp != nil and state.boss_max_hp != nil and state.boss_max_hp > 0 do
          " | boss=#{Float.round(state.boss_hp / state.boss_max_hp * 100, 1)}%HP"
        else
          ""
        end

      Logger.info(
        "[LOOP] #{wave} | scene=#{render_type} | enemies=#{enemy_count} | " <>
          "physics=#{Float.round(physics_ms, 2)}ms#{budget_warn} | " <>
          "lv=#{state.level} exp=#{state.exp} | weapons=[#{weapon_info}]" <> boss_info
      )

      :telemetry.execute(
        [:game, :tick],
        %{physics_ms: physics_ms, enemy_count: enemy_count},
        %{phase: render_type, wave: wave}
      )

      # フェーズ0: 60フレームごとに Rust 側との状態比較ログ
      maybe_snapshot_check(state)
    end
    state
  end

  # フェーズ0-3: Rust 側の状態と Elixir 側の状態を比較して乖離を検出
  defp maybe_snapshot_check(state) do
    try do
      {rust_score, _rust_level, _rust_exp, _rust_hp, _rust_elapsed, rust_kill_count} =
        GameEngine.NifBridge.get_full_game_state(state.world_ref)

      if rust_score != state.score do
        Logger.warning(
          "[SSOT CHECK] score mismatch: elixir=#{state.score} rust=#{rust_score} diff=#{state.score - rust_score}"
        )
      end

      if rust_kill_count != state.kill_count do
        Logger.warning(
          "[SSOT CHECK] kill_count mismatch: elixir=#{state.kill_count} rust=#{rust_kill_count}"
        )
      end
    rescue
      e -> Logger.debug("[SSOT CHECK] snapshot check failed: #{inspect(e)}")
    end
  end

  # ── ユーティリティ ────────────────────────────────────────────────

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp current_rule, do: GameEngine.Config.current_rule()
  defp current_world, do: GameEngine.Config.current_world()

  # Playing シーンの state を SceneManager 経由で更新する（スタック内のどの位置にあっても更新）
  defp update_playing_scene_state(rule, fun) when is_function(fun, 1) do
    GameEngine.SceneManager.update_by_module(rule.playing_scene(), fun)
  end

  # Playing シーンの weapon_levels を取得する（ログ用）
  defp get_playing_scene_weapon_levels(rule) do
    Map.get(get_playing_scene_state(rule), :weapon_levels, %{})
  end

  # Playing シーンの state を取得する
  defp get_playing_scene_state(rule) do
    GameEngine.SceneManager.get_scene_state(rule.playing_scene())
  end

  # セーブロード後に Elixir 側の状態をリセット
  # replace_scene が Playing.init/1 を呼ぶためシーン state は自動的にリセットされる
  defp reset_elixir_state(state) do
    %{state |
      score:         0,
      kill_count:    0,
      elapsed_ms:    0,
      player_hp:     100.0,
      player_max_hp: 100.0,
      level:         1,
      exp:           0,
      exp_to_next:   exp_required_for_next(1),
      boss_hp:       nil,
      boss_max_hp:   nil,
      boss_kind_id:  nil,
    }
  end

  # EXP テーブルの SSoT は game_simulation::util::exp_required_for_next（Rust 側）。
  # Elixir 側はこの NIF を呼び出すことで、Rust と同一の値を参照する。
  defp exp_required_for_next(level) do
    GameEngine.NifBridge.exp_required_for_next_nif(level)
  end

end
