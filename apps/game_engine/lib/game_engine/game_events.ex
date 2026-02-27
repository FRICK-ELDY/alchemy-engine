defmodule GameEngine.GameEvents do
  @moduledoc """
  Rust からの frame_events を受信し、フェーズ管理・NIF 呼び出しを行う GenServer。

  Rust 側が高精度 60 Hz でゲームループを駆動し、
  Elixir は `{:frame_events, events}` を受信してイベント駆動でシーン制御を行う。
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

    map_id = Application.get_env(:game_server, :map, :plain)
    obstacles = GameEngine.MapLoader.obstacles_for_map(map_id)
    GameEngine.NifBridge.set_map_obstacles(world_ref, obstacles)

    control_ref = GameEngine.NifBridge.create_game_loop_control()
    if room_id == :main, do: GameEngine.FrameCache.init()
    start_ms = now_ms()

    GameEngine.NifBridge.start_rust_game_loop(world_ref, control_ref, self())

    if room_id == :main, do: GameEngine.NifBridge.start_render_thread(world_ref)

    initial_weapon_levels = fetch_weapon_levels(world_ref)

    {:ok, %{
      room_id:        room_id,
      world_ref:      world_ref,
      control_ref:    control_ref,
      last_tick:      start_ms,
      frame_count:    0,
      start_ms:       start_ms,
      last_spawn_ms:  start_ms,
      weapon_levels:  initial_weapon_levels,
    }}
  end

  @impl true
  def terminate(_reason, %{room_id: :main}) do
    GameEngine.RoomRegistry.unregister(:main)
    :ok
  end
  def terminate(_reason, _state), do: :ok

  @impl true
  def handle_cast({:select_weapon, :__skip__}, state) do
    game = current_game()
    level_up_scene = game.level_up_scene()

    case GameEngine.SceneManager.current() do
      {:ok, %{module: ^level_up_scene}} ->
        GameEngine.NifBridge.skip_level_up(state.world_ref)
        Logger.info("[LEVEL UP] Skipped weapon selection -> resuming")
        GameEngine.NifBridge.resume_physics(state.control_ref)
        GameEngine.SceneManager.pop_scene()
        {:noreply, %{state | weapon_levels: fetch_weapon_levels(state.world_ref)}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:select_weapon, weapon}, state) do
    game = current_game()
    level_up_scene = game.level_up_scene()

    case GameEngine.SceneManager.current() do
      {:ok, %{module: ^level_up_scene}} ->
        GameEngine.NifBridge.add_weapon(state.world_ref, weapon)
        new_weapon_levels = fetch_weapon_levels(state.world_ref)
        lv = Map.get(new_weapon_levels, weapon, 1)
        Logger.info("[LEVEL UP] Weapon selected: #{game.weapon_label(weapon, lv)} -> resuming")
        GameEngine.NifBridge.resume_physics(state.control_ref)
        GameEngine.SceneManager.pop_scene()
        {:noreply, %{state | weapon_levels: new_weapon_levels}}

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

  @impl true
  def handle_call(:load_session, _from, state) do
    game = current_game()
    result = GameEngine.SaveManager.load_session(state.world_ref)

    case result do
      :ok ->
        GameEngine.SceneManager.replace_scene(game.physics_scenes() |> List.first(), %{})
        {:reply, :ok, %{state | weapon_levels: fetch_weapon_levels(state.world_ref)}}

      other ->
        {:reply, other, state}
    end
  end

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

  def handle_info({:frame_events, events}, state) do
    if state.room_id != :main do
      {:noreply, %{state | last_tick: now_ms(), frame_count: state.frame_count + 1}}
    else
      handle_frame_events_main(events, state)
    end
  end

  defp handle_ui_action_skip(state) do
    {_exp, _level, level_up_pending, _exp_to_next} = GameEngine.NifBridge.get_level_up_data(state.world_ref)

    if level_up_pending do
      GameEngine.NifBridge.skip_level_up(state.world_ref)
      Logger.info("[LEVEL UP] Skipped from renderer UI")
      state
      |> maybe_close_level_up_scene()
      |> Map.put(:weapon_levels, fetch_weapon_levels(state.world_ref))
    else
      state
    end
  end

  defp handle_ui_action_weapon(state, weapon) do
    {_exp, _level, level_up_pending, _exp_to_next} = GameEngine.NifBridge.get_level_up_data(state.world_ref)

    if level_up_pending do
      {selected_weapon, new_levels} = apply_weapon_selection(state, weapon)
      if selected_weapon != :__skip__ do
        level = Map.get(new_levels, selected_weapon, 1)
        game = current_game()
        Logger.info("[LEVEL UP] Weapon selected from renderer: #{game.weapon_label(selected_weapon, level)}")
      end

      %{state | weapon_levels: new_levels}
      |> maybe_close_level_up_scene()
    else
      state
    end
  end

  defp apply_weapon_selection(state, weapon_name) when is_binary(weapon_name) do
    requested_weapon =
      try do
        String.to_existing_atom(weapon_name)
      rescue
        ArgumentError -> nil
      end

    game = current_game()
    allowed_weapons = game.entity_registry().weapons |> Map.keys() |> MapSet.new()
    fallback_weapon = Map.keys(state.weapon_levels) |> List.first() || :magic_wand

    cond do
      is_atom(requested_weapon) and MapSet.member?(allowed_weapons, requested_weapon) ->
        GameEngine.NifBridge.add_weapon(state.world_ref, requested_weapon)
        {requested_weapon, fetch_weapon_levels(state.world_ref)}

      MapSet.member?(allowed_weapons, fallback_weapon) ->
        Logger.warning("[LEVEL UP] Renderer weapon '#{weapon_name}' not available. Falling back to #{inspect(fallback_weapon)}.")
        GameEngine.NifBridge.add_weapon(state.world_ref, fallback_weapon)
        {fallback_weapon, fetch_weapon_levels(state.world_ref)}

      true ->
        Logger.warning("[LEVEL UP] Renderer weapon '#{weapon_name}' not available and no valid fallback. Skipping.")
        GameEngine.NifBridge.skip_level_up(state.world_ref)
        {:__skip__, fetch_weapon_levels(state.world_ref)}
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
        game = current_game()
        GameEngine.SceneManager.replace_scene(game.physics_scenes() |> List.first(), %{})
        %{state | weapon_levels: fetch_weapon_levels(state.world_ref)}

      :no_save ->
        Logger.info("[LOAD] No save data")
        state

      {:error, reason} ->
        Logger.warning("[LOAD] Failed: #{inspect(reason)}")
        state
    end
  end

  defp maybe_close_level_up_scene(state) do
    game = current_game()
    level_up_scene = game.level_up_scene()

    case GameEngine.SceneManager.current() do
      {:ok, %{module: ^level_up_scene}} ->
        GameEngine.NifBridge.resume_physics(state.control_ref)
        GameEngine.SceneManager.pop_scene()
        state

      _ ->
        state
    end
  end

  defp handle_frame_events_main(events, state) do
    now = now_ms()
    elapsed = now - state.start_ms

    game = current_game()
    physics_scenes = game.physics_scenes()

    case GameEngine.SceneManager.current() do
      :empty ->
        {:noreply, %{state | last_tick: now}}

      {:ok, %{module: mod, state: scene_state}} ->
        state = maybe_set_input_and_broadcast(state, mod, physics_scenes, events)

        context = build_context(state, now, elapsed)
        result = mod.update(context, scene_state)

        {new_scene_state, opts} = extract_state_and_opts(result)
        GameEngine.SceneManager.update_current(fn _ -> new_scene_state end)

        state = apply_context_updates(state, opts)
        state = process_transition(result, state, now, game)
        state = maybe_log_and_cache(state, mod, elapsed, game)

        {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}
    end
  end

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

  defp build_context(state, now, elapsed) do
    base = %{
      tick_ms:       @tick_ms,
      world_ref:     state.world_ref,
      now:           now,
      elapsed:       elapsed,
      last_spawn_ms: state.last_spawn_ms,
      weapon_levels: state.weapon_levels,
      frame_count:   state.frame_count,
      start_ms:      state.start_ms,
    }
    game = current_game()
    Map.merge(game.context_defaults(), base)
  end

  defp extract_state_and_opts({:continue, scene_state}), do: {scene_state, %{}}
  defp extract_state_and_opts({:continue, scene_state, opts}), do: {scene_state, opts || %{}}
  defp extract_state_and_opts({:transition, _action, scene_state}), do: {scene_state, %{}}
  defp extract_state_and_opts({:transition, _action, scene_state, opts}), do: {scene_state, opts || %{}}

  defp apply_context_updates(state, %{context_updates: updates}) when is_map(updates) do
    Map.merge(state, updates)
  end
  defp apply_context_updates(state, _), do: state

  defp process_transition({:continue, _, _}, state, _now, _game), do: state

  defp process_transition({:transition, :pop, scene_state}, state, _now, game) do
    auto_select = Map.get(scene_state, :auto_select, false)

    if auto_select do
      state =
        case scene_state do
          %{choices: [first | _]} ->
            GameEngine.NifBridge.add_weapon(state.world_ref, first)
            new_levels = fetch_weapon_levels(state.world_ref)
            Logger.info("[LEVEL UP] Auto-selected: #{game.weapon_label(first, Map.get(new_levels, first, 1))} -> resuming")
            %{state | weapon_levels: new_levels}
          _ ->
            GameEngine.NifBridge.skip_level_up(state.world_ref)
            Logger.info("[LEVEL UP] Auto-skipped (no choices) -> resuming")
            state
        end
      GameEngine.NifBridge.resume_physics(state.control_ref)
      GameEngine.SceneManager.pop_scene()
    else
      GameEngine.NifBridge.resume_physics(state.control_ref)
      GameEngine.SceneManager.pop_scene()
    end
    state
  end

  defp process_transition({:transition, {:push, mod, init_arg}, _}, state, _now, game) do
    if mod == game.level_up_scene() or mod == game.boss_alert_scene() do
      GameEngine.NifBridge.pause_physics(state.control_ref)
    end
    GameEngine.SceneManager.push_scene(mod, init_arg)
    state
  end

  defp process_transition({:transition, {:replace, mod, init_arg}, _}, state, now, game) do
    game_over_scene = game.game_over_scene()

    init_arg =
      if mod == game_over_scene do
        {{_hp, _max_hp, score, _elapsed}, _counts, _level_up, _boss} =
          GameEngine.NifBridge.get_frame_metadata(state.world_ref)

        :telemetry.execute(
          [:game, :session_end],
          %{elapsed_seconds: (now - state.start_ms) / 1000.0, score: score},
          %{}
        )

        GameEngine.SaveManager.save_high_score(score)
        Map.merge(init_arg || %{}, %{high_scores: GameEngine.SaveManager.load_high_scores()})
      else
        init_arg || %{}
      end

    GameEngine.SceneManager.replace_scene(mod, init_arg)
    state
  end

  defp process_transition(_, state, _, _), do: state

  defp maybe_log_and_cache(state, _mod, _elapsed, game) do
    if state.room_id == :main and rem(state.frame_count, 60) == 0 do
      {{hp, max_hp, score, elapsed_s}, {enemy_count, bullet_count, physics_ms},
       {exp, level, _level_up_pending, _exp_to_next}, {boss_alive, boss_hp, boss_max_hp}} =
        GameEngine.NifBridge.get_frame_metadata(state.world_ref)

      hud_data = {hp, max_hp, score, elapsed_s}
      render_type = GameEngine.SceneManager.render_type()
      high_scores = if render_type == :game_over, do: GameEngine.SaveManager.load_high_scores(), else: nil
      GameEngine.FrameCache.put(enemy_count, bullet_count, physics_ms, hud_data, render_type, high_scores)

      wave = game.wave_label(elapsed_s)
      budget_warn = if physics_ms > @tick_ms, do: " [OVER BUDGET]", else: ""

      weapon_info =
        state.weapon_levels
        |> Enum.map_join(", ", fn {w, lv} -> "#{w}:Lv#{lv}" end)

      boss_info =
        if boss_alive and boss_max_hp > 0 do
          " | boss=#{Float.round(boss_hp / boss_max_hp * 100, 1)}%HP"
        else
          ""
        end

      Logger.info(
        "[LOOP] #{wave} | scene=#{render_type} | enemies=#{enemy_count} | " <>
          "physics=#{Float.round(physics_ms, 2)}ms#{budget_warn} | " <>
          "lv=#{level} exp=#{exp} | weapons=[#{weapon_info}]" <> boss_info
      )

      :telemetry.execute(
        [:game, :tick],
        %{physics_ms: physics_ms, enemy_count: enemy_count},
        %{phase: render_type, wave: wave}
      )
    end
    state
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp current_game do
    Application.get_env(:game_server, :current_game, GameContent.VampireSurvivor)
  end

  defp fetch_weapon_levels(world_ref) do
    world_ref
    |> GameEngine.NifBridge.get_weapon_levels()
    |> Map.new(fn {name, level} -> {String.to_existing_atom(name), level} end)
  end
end
