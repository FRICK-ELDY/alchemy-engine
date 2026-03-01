defmodule GameEngine.GameEvents do
  @moduledoc """
  Rust からの frame_events を受信し、コンポーネントへ委譲する GenServer。

  Rust 側が高精度 60 Hz でゲームループを駆動し、
  Elixir は `{:frame_events, events}` を受信してイベント駆動でシーン制御を行う。

  ## 設計原則
  - エンジンはディスパッチのみ行う（ゲームロジックを知らない）
  - ゲーム固有の状態（score, player_hp 等）はシーン state で管理する
  - NIF 注入はコンポーネントの `on_nif_sync/1` が担う
  - フレームイベント処理はコンポーネントの `on_frame_event/2` が担う
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
       render_started: render_started
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
        {:reply, :ok, state}

      other ->
        {:reply, other, state}
    end
  end

  # ── インフォ: UI アクション ──────────────────────────────────────

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

  # ── インフォ: 移動入力 ────────────────────────────────────────────

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

  # 60Hz × 2秒分のバッファ。これを超えた場合、Elixir が GC ポーズや重いシーン遷移で
  # 2秒以上遅延していることを意味し、フレームをドロップして追いつく必要がある。
  # フレームレートが変わった場合（例: 30Hz 環境では 4秒分）は要調整。
  @backpressure_threshold 120

  def handle_info({:frame_events, events}, state) do
    throttled? =
      case Process.info(self(), :message_queue_len) do
        {:message_queue_len, depth} when depth > @backpressure_threshold ->
          :telemetry.execute([:game, :frame_dropped], %{depth: depth}, %{room_id: state.room_id})
          true

        _ ->
          false
      end

    if state.room_id != :main do
      # frame_count は「受信したフレーム数」として管理する（ドロップ分も含む）
      # last_tick はここで更新する（:main は handle_frame_events_main の末尾で更新）
      {:noreply, %{state | last_tick: now_ms(), frame_count: state.frame_count + 1}}
    else
      # :main ルームの last_tick は handle_frame_events_main の末尾で常に更新される
      handle_frame_events_main(events, state, throttled?)
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
        state

      :no_save ->
        Logger.info("[LOAD] No save data")
        state

      {:error, reason} ->
        Logger.warning("[LOAD] Failed: #{inspect(reason)}")
        state
    end
  end

  # ── メインフレームループ ──────────────────────────────────────────

  # throttled?: true のとき、ゲーム整合性に影響するイベント処理（スコア・HP 等）は
  # 維持しつつ、NIF 書き込み・ブロードキャスト等の重い副作用をスキップして追いつく。
  defp handle_frame_events_main(events, state, throttled?) do
    now = now_ms()
    elapsed = now - state.start_ms
    content = current_content()
    physics_scenes = content.physics_scenes()

    case GameEngine.SceneManager.current() do
      :empty ->
        {:noreply, %{state | last_tick: now}}

      {:ok, %{module: mod, state: scene_state}} ->
        context = build_context(state, now, elapsed)

        # ── バックプレッシャー時もスキップしない処理 ──────────────────────
        # スコア・HP・レベルアップ等のゲーム整合性に影響するため常に実行する

        Enum.each(events, &dispatch_frame_event_to_components(&1, context))

        # シーン update（遷移判断のみ）
        result = mod.update(context, scene_state)
        {new_scene_state, _opts} = extract_state_and_opts(result)
        GameEngine.SceneManager.update_current(fn _ -> new_scene_state end)

        state = process_transition(result, state, now, content)

        # ── バックプレッシャー時にスキップする処理 ────────────────────────
        # NIF 書き込み・物理コールバック・ブロードキャスト・ログは重い副作用のためスキップ

        unless throttled? do
          # 入力・物理コールバック・ブロードキャスト
          # on_physics_process（ボス AI 等）が NIF の状態を書き換えるため、
          # on_nif_sync より先に実行する
          maybe_set_input_and_broadcast(state, mod, physics_scenes, events, context)

          # NIF 注入をコンポーネントに委譲
          # on_physics_process の後に実行することで、物理 AI の結果を含めた
          # 最新のシーン state を Rust 側に反映できる
          dispatch_nif_sync_to_components(context)

          # ログ・キャッシュ（60フレームごと）
          GameEngine.GameEvents.Diagnostics.maybe_log_and_cache(state, mod, elapsed, content)
        end

        # frame_count は「受信したフレーム数」として管理する（ドロップ分も含む）
        {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}
    end
  end

  defp dispatch_frame_event_to_components(event, context) do
    dispatch_to_components(:on_frame_event, [event, context])
  end

  defp dispatch_nif_sync_to_components(context) do
    dispatch_to_components(:on_nif_sync, [context])
  end

  defp dispatch_event_to_components(event, context) do
    dispatch_to_components(:on_event, [event, context])
  end

  defp run_component_physics_callbacks(context) do
    dispatch_to_components(:on_physics_process, [context])
  end

  defp dispatch_to_components(callback, args) do
    arity = length(args)

    Enum.each(GameEngine.Config.components(), fn component ->
      if function_exported?(component, callback, arity) do
        apply(component, callback, args)
      end
    end)
  end

  defp maybe_set_input_and_broadcast(state, mod, physics_scenes, events, context) do
    if mod in physics_scenes do
      if state.room_id != :main do
        {dx, dy} = GameEngine.InputHandler.get_move_vector()
        GameEngine.NifBridge.set_player_input(state.world_ref, dx * 1.0, dy * 1.0)
      end

      run_component_physics_callbacks(context)

      unless events == [], do: GameEngine.EventBus.broadcast(events)
    end

    :ok
  end

  defp build_context(state, now, elapsed) do
    control_ref = state.control_ref

    base = %{
      tick_ms: @tick_ms,
      world_ref: state.world_ref,
      now: now,
      elapsed: elapsed,
      frame_count: state.frame_count,
      start_ms: state.start_ms,
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

  defp process_transition({:transition, {:replace, mod, init_arg}, _}, state, now, content) do
    elapsed = now - state.start_ms

    init_arg =
      GameEngine.GameEvents.Diagnostics.build_replace_init_arg(
        mod,
        init_arg,
        elapsed,
        content
      )

    GameEngine.SceneManager.replace_scene(mod, init_arg)
    state
  end

  defp process_transition(_, state, _, _), do: state

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp current_content, do: GameEngine.Config.current()
end
