defmodule Contents.GameEvents do
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

  alias Contents.GameEvents.Diagnostics

  @tick_ms 16

  def start_link(opts \\ []) do
    room_id = Keyword.get(opts, :room_id, :main)
    name = process_name(room_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  defp process_name(:main), do: __MODULE__
  defp process_name(room_id), do: {:via, Registry, {Core.RoomRegistry, room_id}}

  def save_session, do: GenServer.cast(__MODULE__, :save_session)

  def load_session, do: GenServer.call(__MODULE__, :load_session, 5_000)

  @impl true
  def init(opts) do
    room_id = Keyword.get(opts, :room_id, :main)

    if room_id == :main do
      Core.RoomRegistry.register(:main)
    end

    world_ref = Core.NifBridge.create_world()

    Enum.each(Core.Config.components(), fn component ->
      init_component(component, world_ref)
    end)

    map_id = Application.get_env(:server, :map, :plain)
    obstacles = Core.MapLoader.obstacles_for_map(map_id)
    Core.NifBridge.set_map_obstacles(world_ref, obstacles)

    control_ref = Core.NifBridge.create_game_loop_control()
    if room_id == :main, do: Core.FrameCache.init()
    start_ms = now_ms()

    Core.NifBridge.start_rust_game_loop(world_ref, control_ref, self())

    render_buf_ref = Core.NifBridge.create_render_frame_buffer()

    render_started =
      if room_id == :main do
        content = current_content()
        window_title = build_window_title(content)
        atlas_path = resolve_atlas_path(content)

        Core.NifBridge.start_render_thread(
          world_ref,
          render_buf_ref,
          self(),
          window_title,
          atlas_path
        )

        true
      else
        false
      end

    {:ok,
     %{
       room_id: room_id,
       world_ref: world_ref,
       control_ref: control_ref,
       render_buf_ref: render_buf_ref,
       last_tick: start_ms,
       frame_count: 0,
       start_ms: start_ms,
       render_started: render_started
     }}
  end

  @impl true
  def terminate(_reason, %{room_id: :main}) do
    Core.RoomRegistry.unregister(:main)
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
    weapon_slots = get_weapon_slots_for_save(state)
    opts = [weapon_slots: weapon_slots]

    case Core.SaveManager.save_session(state.world_ref, opts) do
      :ok -> Logger.info("[SAVE] Session saved")
      {:error, reason} -> Logger.warning("[SAVE] Failed: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  # ── コール: セッションロード ────────────────────────────────────────

  @impl true
  def handle_call(:load_session, _from, state) do
    content = current_content()
    result = Core.SaveManager.load_session(state.world_ref)

    case result do
      {:ok, loaded_state} ->
        case content.flow_runner(state.room_id) do
          nil ->
            {:reply, {:error, :flow_runner_unavailable}, state}

          runner ->
            initial_state = build_loaded_scene_state(content, loaded_state)
            physics_scene = content.physics_scenes() |> List.first()
            GenServer.call(runner, {:replace, physics_scene, initial_state})
            {:reply, :ok, state}
        end

      :no_save ->
        {:reply, :no_save, state}

      {:error, _} = err ->
        {:reply, err, state}
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

        _ ->
          now = now_ms()
          context = build_context(state, now, now - state.start_ms, flow_runner(state))
          dispatch_event_to_components({:ui_action, action}, context)
          state
      end

    {:noreply, new_state}
  end

  # ── インフォ: 移動入力 ────────────────────────────────────────────

  def handle_info({:move_input, dx, dy}, state) do
    # set_player_input は maybe_set_input_and_broadcast でフレームごとに ETS から読んで行う。
    # ここではコンポーネントへのディスパッチのみ（InputComponent 等がシーン state を更新する）。

    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:move_input, dx, dy}, context)
    {:noreply, state}
  end

  # ── インフォ: マウスデルタ ────────────────────────────────────────

  def handle_info({:mouse_delta, dx, dy}, state) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:mouse_delta, dx, dy}, context)
    {:noreply, state}
  end

  # ── インフォ: スプリント ──────────────────────────────────────────

  def handle_info({:sprint, pressed}, state) when is_boolean(pressed) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:sprint, pressed}, context)
    {:noreply, state}
  end

  # ── インフォ: 生入力イベント（Rust → InputHandler → 意味論的イベント）──

  def handle_info({:raw_key, key, key_state}, state)
      when is_atom(key) and key_state in [:pressed, :released] do
    Core.InputHandler.raw_key(key, key_state)
    {:noreply, state}
  end

  def handle_info({:raw_mouse_motion, dx, dy}, state) when is_number(dx) and is_number(dy) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:mouse_delta, dx * 1.0, dy * 1.0}, context)
    {:noreply, state}
  end

  def handle_info(:focus_lost, state) do
    Core.InputHandler.focus_lost()
    {:noreply, state}
  end

  # ── インフォ: VR 入力イベント（input_openxr → nif 経由）───────
  # position: {x,y,z}, orientation: {qx,qy,qz,qw}, velocity: {vx,vy,vz}
  # 不正なペイロードはフォールバックで無視しクラッシュを防ぐ。

  def handle_info(
        {:head_pose, {position, orientation, timestamp}},
        state
      )
      when is_tuple(position) and tuple_size(position) == 3 and
             is_tuple(orientation) and tuple_size(orientation) == 4 and
             is_number(timestamp) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    data = %{position: position, orientation: orientation, timestamp: timestamp}
    dispatch_event_to_components({:head_pose, data}, context)
    {:noreply, state}
  end

  def handle_info(
        {:controller_pose, {hand, position, orientation, timestamp}},
        state
      )
      when hand in [:left, :right] and
             is_tuple(position) and tuple_size(position) == 3 and
             is_tuple(orientation) and tuple_size(orientation) == 4 and
             is_number(timestamp) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    data = %{hand: hand, position: position, orientation: orientation, timestamp: timestamp}
    dispatch_event_to_components({:controller_pose, data}, context)
    {:noreply, state}
  end

  def handle_info({:controller_button, {hand, button, pressed}}, state)
      when hand in [:left, :right] and is_atom(button) and is_boolean(pressed) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    data = %{hand: hand, button: button, pressed: pressed}
    dispatch_event_to_components({:controller_button, data}, context)
    {:noreply, state}
  end

  def handle_info(
        {:tracker_pose, {tracker_id, position, orientation, velocity, timestamp}},
        state
      )
      when is_tuple(position) and tuple_size(position) == 3 and
             is_tuple(orientation) and tuple_size(orientation) == 4 and
             (is_nil(velocity) or (is_tuple(velocity) and tuple_size(velocity) == 3)) and
             is_number(timestamp) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))

    data = %{
      tracker_id: tracker_id,
      position: position,
      orientation: orientation,
      velocity: velocity,
      timestamp: timestamp
    }

    dispatch_event_to_components({:tracker_pose, data}, context)
    {:noreply, state}
  end

  # 不正な VR イベントはログして無視（クラッシュ防止）
  def handle_info({:head_pose, _}, state) do
    Logger.warning("[VR] Ignoring malformed head_pose")
    {:noreply, state}
  end

  def handle_info({:controller_pose, _}, state) do
    Logger.warning("[VR] Ignoring malformed controller_pose")
    {:noreply, state}
  end

  def handle_info({:controller_button, _}, state) do
    Logger.warning("[VR] Ignoring malformed controller_button")
    {:noreply, state}
  end

  def handle_info({:tracker_pose, _}, state) do
    Logger.warning("[VR] Ignoring malformed tracker_pose")
    {:noreply, state}
  end

  # ── インフォ: キー押下（InputHandler が raw_key から生成）───────────────

  def handle_info({:key_pressed, key}, state) when is_atom(key) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:key_pressed, key}, context)
    {:noreply, state}
  end

  # ── インフォ: エンジン内部メッセージ（汎用ディスパッチ）──────────────────
  # コンポーネントが Process.send_after 等で送った遅延メッセージを
  # on_engine_message/2 で該当コンポーネントに転送する

  def handle_info({:boss_dash_end, _world_ref} = msg, state) do
    context = %{world_ref: state.world_ref}
    dispatch_to_components(:on_engine_message, [msg, context])
    {:noreply, state}
  end

  # ── インフォ: ネットワークイベント（接続ルームからのブロードキャスト）──
  # FormulaStore.synced の更新を他ルームから受信したときに適用する
  def handle_info({:network_event, _from_room, {:formula_store_synced, key, value}}, state) do
    Core.FormulaStore.apply_synced_from_network(state.room_id, key, value)
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
    if Core.SaveManager.has_save?() do
      do_load_session(state)
    else
      Logger.info("[LOAD] No save file")
      state
    end
  end

  defp handle_ui_action_load_confirm(state), do: do_load_session(state)

  defp do_load_session(state) do
    case Core.SaveManager.load_session(state.world_ref) do
      {:ok, loaded_state} ->
        content = current_content()

        case content.flow_runner(state.room_id) do
          nil ->
            Logger.warning(
              "[LOAD] Session loaded but flow_runner unavailable, scene not replaced"
            )

            state

          runner ->
            initial_state = build_loaded_scene_state(content, loaded_state)
            physics_scene = content.physics_scenes() |> List.first()
            GenServer.call(runner, {:replace, physics_scene, initial_state})
            state
        end

      :no_save ->
        Logger.info("[LOAD] No save data")
        state

      {:error, reason} ->
        Logger.warning("[LOAD] Failed: #{inspect(reason)}")
        state
    end
  end

  defp get_weapon_slots_for_save(state) do
    content = current_content()
    runner = content.flow_runner(state.room_id)

    if runner && function_exported?(content, :weapon_levels_to_save_format, 1) do
      playing_state =
        Contents.SceneStack.get_scene_state(runner, content.playing_scene()) || %{}

      weapon_levels = Map.get(playing_state, :weapon_levels, %{})
      content.weapon_levels_to_save_format(weapon_levels)
    else
      []
    end
  end

  defp build_loaded_scene_state(content, loaded_state) do
    base =
      %{}
      |> maybe_put(:player_hp, loaded_state["player_hp"])
      |> maybe_put(:player_max_hp, loaded_state["player_max_hp"])
      |> maybe_put(:elapsed_ms, elapsed_ms_from_loaded(loaded_state))

    if function_exported?(content, :weapon_slots_to_levels, 1) do
      slots = loaded_state["weapon_slots"] || []
      weapon_levels = content.weapon_slots_to_levels(slots)
      Map.merge(base, %{weapon_levels: weapon_levels, weapon_cooldowns: %{}})
    else
      base
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp elapsed_ms_from_loaded(%{"elapsed_seconds" => sec}) when is_number(sec),
    do: trunc(sec * 1000)

  defp elapsed_ms_from_loaded(_), do: nil

  # ── メインフレームループ ──────────────────────────────────────────

  # throttled?: true のとき、ゲーム整合性に影響するイベント処理（スコア・HP 等）は
  # 維持しつつ、NIF 書き込み・ブロードキャスト等の重い副作用をスキップして追いつく。
  defp handle_frame_events_main(events, state, throttled?) do
    now = now_ms()
    elapsed = now - state.start_ms
    content = current_content()
    physics_scenes = content.physics_scenes()
    runner = content.flow_runner(state.room_id)

    # runner が nil のときは short-circuit で GenServer.call を避ける。
    # runner が有効な pid でもプロセス終了済みの場合は GenServer.call が exit する。
    case runner && GenServer.call(runner, :current) do
      nil ->
        # flow_runner 未使用（起動前等）。frame_count は受信フレーム数として更新する。
        {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}

      :empty ->
        # スタック空。同上。
        {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}

      {:ok, %{module: mod, state: scene_state}} ->
        context = build_context(state, now, elapsed, runner)

        # ── バックプレッシャー時もスキップしない処理 ──────────────────────
        # スコア・HP・レベルアップ等のゲーム整合性に影響するため常に実行する

        Enum.each(events, &dispatch_frame_event_to_components(&1, context))

        # シーン update（遷移判断のみ）
        result = mod.update(context, scene_state)
        {new_scene_state, _opts} = extract_state_and_opts(result)
        GenServer.call(runner, {:update_current, fn _ -> new_scene_state end})

        state = process_transition(result, state, now, content, runner)

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
          Diagnostics.maybe_log_and_cache(state, mod, elapsed, content, runner)
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

    Enum.each(Core.Config.components(), fn component ->
      if function_exported?(component, callback, arity) do
        apply(component, callback, args)
      end
    end)
  end

  defp maybe_set_input_and_broadcast(state, mod, physics_scenes, events, context) do
    if mod in physics_scenes do
      # 全ルームでフレームごとに ETS から読む。InputHandler が raw_key で ETS を更新するため、
      # メッセージ順序（frame_events vs move_input）に依存せず入力が 1 フレーム遅れない。
      {dx, dy} = Core.InputHandler.get_move_vector()
      Core.NifBridge.set_player_input(state.world_ref, dx * 1.0, dy * 1.0)

      run_component_physics_callbacks(context)

      unless events == [], do: Core.EventBus.broadcast(events)
    end

    :ok
  end

  defp flow_runner(state), do: current_content().flow_runner(state.room_id)

  defp build_context(state, now, elapsed, runner) do
    control_ref = state.control_ref
    content = current_content()

    base = %{
      tick_ms: @tick_ms,
      world_ref: state.world_ref,
      render_buf_ref: state.render_buf_ref,
      now: now,
      elapsed: elapsed,
      frame_count: state.frame_count,
      start_ms: state.start_ms,
      push_scene: fn mod, init_arg ->
        if runner do
          if function_exported?(content, :pause_on_push?, 1) and content.pause_on_push?(mod) do
            Core.NifBridge.pause_physics(control_ref)
          end

          GenServer.call(runner, {:push, mod, init_arg})
        else
          :ok
        end
      end,
      pop_scene: fn ->
        Core.NifBridge.resume_physics(control_ref)
        if runner, do: GenServer.call(runner, :pop), else: :ok
      end,
      replace_scene: fn mod, init_arg ->
        if runner, do: GenServer.call(runner, {:replace, mod, init_arg}), else: :ok
      end
    }

    Map.merge(content.context_defaults(), base)
  end

  defp extract_state_and_opts({:continue, scene_state}), do: {scene_state, %{}}
  defp extract_state_and_opts({:continue, scene_state, opts}), do: {scene_state, opts || %{}}
  defp extract_state_and_opts({:transition, _action, scene_state}), do: {scene_state, %{}}

  defp extract_state_and_opts({:transition, _action, scene_state, opts}),
    do: {scene_state, opts || %{}}

  # runner は handle_frame_events_main の {:ok, ...} 経路からのみ渡されるため常に non-nil
  defp process_transition({:continue, _}, state, _now, _content, _runner), do: state
  defp process_transition({:continue, _, _}, state, _now, _content, _runner), do: state

  defp process_transition({:transition, :pop, scene_state}, state, now, _content, runner) do
    auto_select = Map.get(scene_state, :auto_select, false)

    if auto_select do
      context = build_context(state, now, now - state.start_ms, runner)
      dispatch_event_to_components({:ui_action, "__auto_pop__", scene_state}, context)
    end

    Core.NifBridge.resume_physics(state.control_ref)
    GenServer.call(runner, :pop)
    state
  end

  defp process_transition({:transition, {:push, mod, init_arg}, _}, state, _now, content, runner) do
    should_pause =
      function_exported?(content, :pause_on_push?, 1) and content.pause_on_push?(mod)

    if should_pause do
      Core.NifBridge.pause_physics(state.control_ref)
    end

    GenServer.call(runner, {:push, mod, init_arg})
    state
  end

  defp process_transition(
         {:transition, {:replace, mod, init_arg}, _},
         state,
         now,
         content,
         runner
       ) do
    elapsed = now - state.start_ms

    init_arg =
      Diagnostics.build_replace_init_arg(
        mod,
        init_arg,
        elapsed,
        content,
        runner
      )

    GenServer.call(runner, {:replace, mod, init_arg})
    state
  end

  defp process_transition(_, state, _, _, _), do: state

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp current_content, do: Core.Config.current()

  defp build_window_title(content) do
    if function_exported?(content, :title, 0) do
      "AlchemyEngine - #{content.title()}"
    else
      "AlchemyEngine"
    end
  end

  # アトラス PNG のファイルパスを解決して返す。
  # Elixir 側はパス文字列のみを持ち、ファイルの実態（バイナリ）は持たない。
  # 実際のロードは Rust 側（render_bridge）で行う。
  #
  # パス解決の優先順位:
  #   1. $GAME_ASSETS_PATH/assets/{game_assets_id}/sprites/atlas.png
  #   2. assets/{game_assets_id}/sprites/atlas.png（カレントディレクトリ基準）
  #   3. $GAME_ASSETS_PATH/assets/sprites/atlas.png
  #   4. assets/sprites/atlas.png（カレントディレクトリ基準）
  #
  # ファイルが存在しない場合は Rust 側の埋め込みフォールバックが使用される。
  #
  # `assets_path/0` が返す値はゲーム別サブディレクトリ名（例: "vampire_survivor"）。
  # 環境変数 GAME_ASSETS_PATH が空文字列の場合はカレントディレクトリと同等に扱う。
  defp resolve_atlas_path(content) do
    game_assets_id =
      if function_exported?(content, :assets_path, 0), do: content.assets_path(), else: nil

    base =
      case System.get_env("GAME_ASSETS_PATH") do
        nil -> "."
        "" -> "."
        path -> path
      end

    if game_assets_id do
      Path.join([base, "assets", game_assets_id, "sprites", "atlas.png"])
    else
      Path.join([base, "assets", "sprites", "atlas.png"])
    end
  end
end
