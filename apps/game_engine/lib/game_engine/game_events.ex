defmodule GameEngine.GameEvents do
  @moduledoc """
  Rust からの frame_events を受信し、フェーズ管理・NIF 呼び出しを行う GenServer。

  Rust 側が高精度 60 Hz でゲームループを駆動し、
  Elixir は `{:frame_events, events}` を受信してイベント駆動でシーン制御を行う。

  ## Elixir as SSoT 移行状況
  - フェーズ1完了: score, kill_count, elapsed_ms を Elixir 側で管理
  - フェーズ2完了: player_hp, player_max_hp を Elixir 側で管理
  - フェーズ3完了: level, exp, exp_to_next を Playing シーン state で管理（エンジン state から除去）
               weapon_levels, level_up_pending, weapon_choices は Playing シーン state で管理
  - フェーズ4完了: boss_hp, boss_max_hp, boss_kind_id を Playing シーン state で管理（エンジン state から除去）
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

    # コンポーネントの on_ready/1 を順に呼び出してワールドを初期化する
    Enum.each(GameEngine.Config.components(), fn component ->
      init_component(component, world_ref)
    end)

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

    {:ok,
     %{
       room_id: room_id,
       world_ref: world_ref,
       control_ref: control_ref,
       last_tick: start_ms,
       frame_count: 0,
       start_ms: start_ms,
       last_spawn_ms: start_ms,
       # フェーズ1: スコア・統計を Elixir 側で管理
       score: 0,
       kill_count: 0,
       elapsed_ms: 0,
       # フェーズ2: プレイヤー HP を Elixir 側で管理
       player_hp: 100.0,
       player_max_hp: 100.0,
       # フェーズ5: 描画スレッド起動済みフラグ
       render_started: render_started,
       # I-3: 前フレームの weapon_levels（差分チェック用）
       last_weapon_levels: nil,
       # I-A: HUD 差分チェック用（前フレームの値）
       last_hud_score: -1,
       last_hud_kill_count: -1,
       last_player_hp: -1.0,
       last_elapsed_ms: -1,
       last_hud_level_state: nil,
       last_boss_hp: :unset
     }}
  end

  @impl true
  def terminate(_reason, %{room_id: :main}) do
    GameEngine.RoomRegistry.unregister(:main)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp init_component(component, world_ref) do
    Code.ensure_loaded(component)

    if function_exported?(component, :on_ready, 1) do
      result = component.on_ready(world_ref)

      if result != :ok do
        Logger.error("[GameEvents] #{inspect(component)}.on_ready/1 failed: #{inspect(result)}")
      end
    end
  end

  # ── キャスト: 武器選択（後方互換性のため残存。UI アクションに委譲）──

  @impl true
  def handle_cast({:select_weapon, :__skip__}, state) do
    send(self(), {:ui_action, "__skip__"})
    {:noreply, state}
  end

  def handle_cast({:select_weapon, weapon}, state) when is_atom(weapon) do
    send(self(), {:ui_action, to_string(weapon)})
    {:noreply, state}
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
    content = current_content()
    result = GameEngine.SaveManager.load_session(state.world_ref)

    case result do
      :ok ->
        GameEngine.SceneManager.replace_scene(content.physics_scenes() |> List.first(), %{})
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
        "__save__" ->
          GenServer.cast(self(), :save_session)
          state

        "__load__" ->
          handle_ui_action_load(state)

        "__load_confirm__" ->
          handle_ui_action_load_confirm(state)

        "__load_cancel__" ->
          state

        "__start__" ->
          state

        "__retry__" ->
          state

        _ ->
          now = now_ms()
          context = build_context(state, now, now - state.start_ms)
          dispatch_event_to_components({:ui_action, action}, context)
          state
      end

    {:noreply, new_state}
  end

  # ── インフォ: 移動入力（フェーズ5: 描画スレッドから直接受信）────────

  def handle_info({:move_input, dx, dy}, state) do
    GameEngine.NifBridge.set_player_input(state.world_ref, dx * 1.0, dy * 1.0)
    {:noreply, state}
  end

  # ── インフォ: ボスダッシュ終了（BatLord AI）────────────────────────

  def handle_info({:boss_dash_end, world_ref}, state) do
    if state.world_ref == world_ref do
      GameEngine.NifBridge.set_boss_invincible(world_ref, false)
      GameEngine.NifBridge.set_boss_velocity(world_ref, 0.0, 0.0)
    end

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
        content = current_content()
        GameEngine.SceneManager.replace_scene(content.physics_scenes() |> List.first(), %{})
        reset_elixir_state(state)

      :no_save ->
        Logger.info("[LOAD] No save data")
        state

      {:error, reason} ->
        Logger.warning("[LOAD] Failed: #{inspect(reason)}")
        state
    end
  end

  # ── メインフレームループ ──────────────────────────────────────────

  defp handle_frame_events_main(events, state) do
    now = now_ms()
    elapsed = now - state.start_ms

    content = current_content()
    physics_scenes = content.physics_scenes()

    case GameEngine.SceneManager.current() do
      :empty ->
        {:noreply, %{state | last_tick: now}}

      {:ok, %{module: mod, state: scene_state}} ->
        delta_ms = now - state.last_tick
        state = %{state | elapsed_ms: state.elapsed_ms + delta_ms}
        state = apply_frame_events(events, state)
        state = sync_nif_state(state, content)
        state = maybe_set_input_and_broadcast(state, mod, physics_scenes, events)

        context = build_context(state, now, elapsed)
        run_component_callbacks(context)

        result = mod.update(context, scene_state)
        {new_scene_state, opts} = extract_state_and_opts(result)
        GameEngine.SceneManager.update_current(fn _ -> new_scene_state end)

        state = apply_context_updates(state, opts)
        state = process_transition(result, state, now, content)
        state = maybe_log_and_cache(state, mod, elapsed, content)

        {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}
    end
  end

  defp sync_nif_state(state, content) do
    state = maybe_update_hud_state(state)
    state = maybe_update_player_hp(state)
    state = maybe_update_elapsed(state)
    playing_state = get_playing_scene_state(content)
    state = maybe_update_hud_level(state, playing_state)
    scene_boss_hp = Map.get(playing_state, :boss_hp)
    state = maybe_update_boss_hp(state, scene_boss_hp)
    weapon_levels = Map.get(playing_state, :weapon_levels)
    maybe_update_weapon_slots(state, content, weapon_levels)
  end

  defp maybe_update_hud_state(state) do
    if state.score != state.last_hud_score or state.kill_count != state.last_hud_kill_count do
      call_nif(:set_hud_state, fn ->
        GameEngine.NifBridge.set_hud_state(state.world_ref, state.score, state.kill_count)
      end)

      %{state | last_hud_score: state.score, last_hud_kill_count: state.kill_count}
    else
      state
    end
  end

  defp maybe_update_player_hp(state) do
    if state.player_hp != state.last_player_hp do
      call_nif(:set_player_hp, fn ->
        GameEngine.NifBridge.set_player_hp(state.world_ref, state.player_hp)
      end)

      %{state | last_player_hp: state.player_hp}
    else
      state
    end
  end

  defp maybe_update_elapsed(state) do
    if state.elapsed_ms != state.last_elapsed_ms do
      elapsed_sec = state.elapsed_ms / 1000.0

      call_nif(:set_elapsed_seconds, fn ->
        GameEngine.NifBridge.set_elapsed_seconds(state.world_ref, elapsed_sec)
      end)

      %{state | last_elapsed_ms: state.elapsed_ms}
    else
      state
    end
  end

  defp maybe_update_hud_level(state, playing_state) do
    case Map.get(playing_state, :level) do
      hud_level when hud_level != nil ->
        push_hud_level_to_nif(state, playing_state, hud_level)

      _ ->
        state
    end
  end

  defp push_hud_level_to_nif(state, playing_state, hud_level) do
    level_up_pending = Map.get(playing_state, :level_up_pending, false)
    weapon_choices = Map.get(playing_state, :weapon_choices, []) |> Enum.map(&to_string/1)
    scene_exp = Map.get(playing_state, :exp, 0)
    scene_exp_to_next = Map.get(playing_state, :exp_to_next, 10)
    new_level_state = {hud_level, scene_exp, scene_exp_to_next, level_up_pending, weapon_choices}

    if new_level_state != state.last_hud_level_state do
      call_nif(:set_hud_level_state, fn ->
        GameEngine.NifBridge.set_hud_level_state(
          state.world_ref,
          hud_level,
          scene_exp,
          scene_exp_to_next,
          level_up_pending,
          weapon_choices
        )
      end)

      %{state | last_hud_level_state: new_level_state}
    else
      state
    end
  end

  defp maybe_update_weapon_slots(state, content, weapon_levels) do
    with true <- weapon_levels != nil,
         true <- weapon_levels != state.last_weapon_levels do
      push_weapon_slots_to_nif(state, content, weapon_levels)
      %{state | last_weapon_levels: weapon_levels}
    else
      _ -> state
    end
  end

  defp push_weapon_slots_to_nif(state, content, weapon_levels) do
    playing_scene = content.playing_scene()

    if function_exported?(playing_scene, :weapon_slots_for_nif, 1) do
      slots = playing_scene.weapon_slots_for_nif(weapon_levels)

      call_nif(:set_weapon_slots, fn ->
        GameEngine.NifBridge.set_weapon_slots(state.world_ref, slots)
      end)
    end
  end

  defp run_component_callbacks(context) do
    Enum.each(GameEngine.Config.components(), fn component ->
      if function_exported?(component, :on_physics_process, 1) do
        component.on_physics_process(context)
      end
    end)
  end

  # ── フレームイベント処理（Elixir 側 SSoT 更新）──────────────────────

  defp apply_frame_events(events, state) do
    Enum.reduce(events, state, &apply_event/2)
  end

  # EnemyKilled でスコア・kill_count を積算し、ポップアップ表示・アイテムドロップを処理する
  # x_bits/y_bits は f32::to_bits() でエンコードされた撃破座標
  defp apply_event({:enemy_killed, enemy_kind, x_bits, y_bits, _}, state) do
    content = current_content()
    exp = content.enemy_exp_reward(enemy_kind)
    x = bits_to_f32(x_bits)
    y = bits_to_f32(y_bits)
    scene = content.playing_scene()
    {state, score_delta} = apply_kill_score(state, exp, content)
    update_playing_scene_state(content, &scene.accumulate_exp(&1, exp))

    call_nif(:add_score_popup, fn ->
      GameEngine.NifBridge.add_score_popup(state.world_ref, x, y, score_delta)
    end)

    now = now_ms()

    dispatch_event_to_components(
      {:entity_removed, state.world_ref, enemy_kind, x, y},
      build_context(state, now, now - state.start_ms)
    )

    state
  end

  # BossDefeated でスコア・kill_count を積算し、ポップアップ表示・アイテムドロップを処理する
  # boss_exp_reward/1 を持つコンテンツ（ボスの概念があるコンテンツ）のみ処理する
  # I-4: ボス種別は Playing シーン state の boss_kind_id から取得する（Rust 側は種別を持たない）
  defp apply_event({:boss_defeated, _, x_bits, y_bits, _}, state) do
    content = current_content()
    playing_state = get_playing_scene_state(content)
    boss_kind = Map.get(playing_state, :boss_kind_id)

    if boss_kind != nil and function_exported?(content, :boss_exp_reward, 1) do
      exp = content.boss_exp_reward(boss_kind)
      x = bits_to_f32(x_bits)
      y = bits_to_f32(y_bits)
      scene = content.playing_scene()
      {state, score_delta} = apply_kill_score(state, exp, content)

      update_playing_scene_state(content, fn s ->
        s
        |> scene.accumulate_exp(exp)
        |> scene.apply_boss_defeated()
      end)

      call_nif(:add_score_popup, fn ->
        GameEngine.NifBridge.add_score_popup(state.world_ref, x, y, score_delta)
      end)

      now = now_ms()

      dispatch_event_to_components(
        {:boss_defeated, state.world_ref, boss_kind, x, y},
        build_context(state, now, now - state.start_ms)
      )

      state
    else
      state
    end
  end

  # PlayerDamaged で Elixir 側 HP を減算
  defp apply_event({:player_damaged, damage_x1000, _, _, _}, state) do
    damage = damage_x1000 / 1000.0
    new_hp = max(0.0, state.player_hp - damage)
    %{state | player_hp: new_hp}
  end

  # BossSpawn でボス状態を Playing シーン state に設定
  defp apply_event({:boss_spawn, boss_kind, _, _, _}, state) do
    content = current_content()
    update_playing_scene_state(content, &content.playing_scene().apply_boss_spawn(&1, boss_kind))
    state
  end

  # BossDamaged でボス HP を Playing シーン state で減算
  defp apply_event({:boss_damaged, damage_x1000, _, _, _}, state) do
    damage = damage_x1000 / 1000.0
    content = current_content()
    update_playing_scene_state(content, &content.playing_scene().apply_boss_damaged(&1, damage))
    state
  end

  defp apply_event({:level_up_event, _, _, _, _}, state), do: state
  defp apply_event({:item_pickup, _, _, _, _}, state), do: state
  defp apply_event(_, state), do: state

  # f32::to_bits() でエンコードされた u32 を Elixir の float に変換する
  defp bits_to_f32(bits) do
    <<f::float-size(32)>> = <<bits::unsigned-size(32)>>
    f
  end

  # スコア・kill_count を state に適用する共通関数
  # 戻り値: {新 state, score_delta}（score_delta はポップアップ表示に使用）
  defp apply_kill_score(state, exp, rule) do
    score_delta = rule.score_from_exp(exp)

    new_state =
      state
      |> Map.update!(:score, &(&1 + score_delta))
      |> Map.update!(:kill_count, &(&1 + 1))

    {new_state, score_delta}
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
    control_ref = state.control_ref

    base = %{
      tick_ms: @tick_ms,
      world_ref: state.world_ref,
      now: now,
      elapsed: elapsed,
      last_spawn_ms: state.last_spawn_ms,
      frame_count: state.frame_count,
      start_ms: state.start_ms,
      score: state.score,
      kill_count: state.kill_count,
      elapsed_ms: state.elapsed_ms,
      player_hp: state.player_hp,
      player_max_hp: state.player_max_hp,
      push_scene: fn mod, init_arg ->
        content = current_content()

        if function_exported?(content, :pause_on_push?, 1) and content.pause_on_push?(mod) do
          GameEngine.NifBridge.pause_physics(control_ref)
        end

        GameEngine.SceneManager.push_scene(mod, init_arg)
      end,
      pop_scene: fn ->
        GameEngine.NifBridge.resume_physics(control_ref)
        GameEngine.SceneManager.pop_scene()
      end,
      replace_scene: fn mod, init_arg ->
        GameEngine.SceneManager.replace_scene(mod, init_arg)
      end
    }

    Map.merge(current_content().context_defaults(), base)
  end

  defp extract_state_and_opts({:continue, scene_state}), do: {scene_state, %{}}
  defp extract_state_and_opts({:continue, scene_state, opts}), do: {scene_state, opts || %{}}
  defp extract_state_and_opts({:transition, _action, scene_state}), do: {scene_state, %{}}

  defp extract_state_and_opts({:transition, _action, scene_state, opts}),
    do: {scene_state, opts || %{}}

  defp apply_context_updates(state, %{context_updates: updates}) when is_map(updates) do
    Map.merge(state, updates)
  end

  defp apply_context_updates(state, _), do: state

  # ── シーン遷移処理 ────────────────────────────────────────────────

  defp process_transition({:continue, _}, state, _now, _content), do: state
  defp process_transition({:continue, _, _}, state, _now, _content), do: state

  defp process_transition({:transition, :pop, scene_state}, state, now, _content) do
    auto_select = Map.get(scene_state, :auto_select, false)

    if auto_select do
      context = build_context(state, now, now - state.start_ms)
      dispatch_event_to_components({:ui_action, "__auto_pop__", scene_state}, context)
    end

    GameEngine.NifBridge.resume_physics(state.control_ref)
    GameEngine.SceneManager.pop_scene()
    state
  end

  defp process_transition({:transition, {:push, mod, init_arg}, _}, state, _now, content) do
    should_pause =
      function_exported?(content, :pause_on_push?, 1) and content.pause_on_push?(mod)

    if should_pause do
      GameEngine.NifBridge.pause_physics(state.control_ref)
    end

    GameEngine.SceneManager.push_scene(mod, init_arg)
    state
  end

  defp process_transition({:transition, {:replace, mod, init_arg}, _}, state, _now, content) do
    game_over_scene = content.game_over_scene()

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

  defp process_transition(_, state, _, _), do: state

  # ── ログ・キャッシュ更新 ──────────────────────────────────────────

  defp maybe_log_and_cache(state, _mod, _elapsed, content) do
    if state.room_id == :main and rem(state.frame_count, 60) == 0 do
      do_log_and_cache(state, content)
    end

    state
  end

  defp do_log_and_cache(state, content) do
    elapsed_s = state.elapsed_ms / 1000.0
    render_type = GameEngine.SceneManager.render_type()
    hud_data = {state.player_hp, state.player_max_hp, state.score, elapsed_s}

    high_scores =
      if render_type == :game_over, do: GameEngine.SaveManager.load_high_scores(), else: nil

    enemy_count = GameEngine.NifBridge.get_enemy_count(state.world_ref)
    bullet_count = GameEngine.NifBridge.get_bullet_count(state.world_ref)
    physics_ms = GameEngine.NifBridge.get_frame_time_ms(state.world_ref)

    GameEngine.FrameCache.put(
      enemy_count,
      bullet_count,
      physics_ms,
      hud_data,
      render_type,
      high_scores
    )

    log_tick(state, content, elapsed_s, render_type, enemy_count, physics_ms)
    maybe_snapshot_check(state)
  end

  defp log_tick(_state, content, elapsed_s, render_type, enemy_count, physics_ms) do
    wave = content.wave_label(elapsed_s)
    budget_warn = if physics_ms > @tick_ms, do: " [OVER BUDGET]", else: ""
    log_playing_state = get_playing_scene_state(content)
    log_exp = Map.get(log_playing_state, :exp, 0)
    log_level = Map.get(log_playing_state, :level, "-")
    weapon_info = format_weapon_info(Map.get(log_playing_state, :weapon_levels))
    boss_info = format_boss_info(log_playing_state)

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
    log_boss_hp = Map.get(playing_state, :boss_hp)
    log_boss_max_hp = Map.get(playing_state, :boss_max_hp)

    if log_boss_hp != nil and log_boss_max_hp != nil and log_boss_max_hp > 0 do
      " | boss=#{Float.round(log_boss_hp / log_boss_max_hp * 100, 1)}%HP"
    else
      ""
    end
  end

  defp maybe_update_boss_hp(state, scene_boss_hp) do
    if scene_boss_hp != state.last_boss_hp do
      push_boss_hp_to_nif(state, scene_boss_hp)
      %{state | last_boss_hp: scene_boss_hp}
    else
      state
    end
  end

  defp push_boss_hp_to_nif(_state, nil), do: :ok

  defp push_boss_hp_to_nif(state, scene_boss_hp) do
    call_nif(:set_boss_hp, fn ->
      GameEngine.NifBridge.set_boss_hp(state.world_ref, scene_boss_hp)
    end)
  end

  # Rust 側の状態と Elixir 側の状態を比較して乖離を検出
  defp maybe_snapshot_check(state) do
    {rust_score, _rust_hp, _rust_elapsed, rust_kill_count} =
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

  # ── ユーティリティ ────────────────────────────────────────────────

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp current_content, do: GameEngine.Config.current()

  defp call_nif(name, fun) do
    case fun.() do
      {:error, reason} ->
        Logger.error("[NIF ERROR] #{name} failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end

  # コンポーネントの on_event/2 を順に呼び出す
  defp dispatch_event_to_components(event, context) do
    Enum.each(GameEngine.Config.components(), fn component ->
      if function_exported?(component, :on_event, 2) do
        component.on_event(event, context)
      end
    end)
  end

  # Playing シーンの state を SceneManager 経由で更新する（スタック内のどの位置にあっても更新）
  defp update_playing_scene_state(content, fun) when is_function(fun, 1) do
    GameEngine.SceneManager.update_by_module(content.playing_scene(), fun)
  end

  # Playing シーンの state を取得する
  defp get_playing_scene_state(content) do
    GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}
  end

  # セーブロード後に Elixir 側の状態をリセット
  # replace_scene が Playing.init/1 を呼ぶためシーン state は自動的にリセットされる
  defp reset_elixir_state(state) do
    %{
      state
      | score: 0,
        kill_count: 0,
        elapsed_ms: 0,
        player_hp: 100.0,
        player_max_hp: 100.0,
        last_weapon_levels: nil,
        last_hud_score: -1,
        last_hud_kill_count: -1,
        last_player_hp: -1.0,
        last_elapsed_ms: -1,
        last_hud_level_state: nil,
        last_boss_hp: :unset
    }
  end
end
