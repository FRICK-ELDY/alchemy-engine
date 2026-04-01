defmodule Contents.Events.Game do
  @moduledoc """
  メインゲームループとコンポーネント委譲を行う GenServer（旧名 GameEvents）。

  `:main` ルームでは Elixir タイマー（約 16ms）で `scene_update` を駆動する。
  ゲーム用 NIF / Rust ゲームループは使わない。`{:frame_events, events}` も従来どおり受け付ける。

  ## 設計原則
  - エンジンはディスパッチのみ行う（ゲームロジックを知らない）
  - ゲーム固有の状態はシーン state で管理する
  - `on_nif_sync/1` は歴史的名称（毎フレームの描画パイプライン同期）
  - `on_frame_event/2` は外部からのイベント列用
  """

  use GenServer
  require Logger

  alias Contents.Events.Game.Diagnostics

  @tick_ms 16

  @stub_world :stub
  @stub_control :stub

  def start_link(opts \\ []) do
    room_id = Keyword.get(opts, :room_id, :main)
    name = process_name(room_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  defp process_name(:main), do: __MODULE__
  defp process_name(room_id), do: {:via, Registry, {Core.RoomRegistry, room_id}}

  @impl true
  def init(opts) do
    room_id = Keyword.get(opts, :room_id, :main)

    if room_id == :main do
      Core.RoomRegistry.register(:main)
    end

    world_ref = @stub_world
    control_ref = @stub_control

    Enum.each(Contents.ComponentList.components(), fn component ->
      init_component(component, world_ref)
    end)

    if room_id == :main do
      Core.FrameCache.init()
      schedule_elixir_frame_tick()
    end

    start_ms = now_ms()

    {:ok,
     %{
       room_id: room_id,
       world_ref: world_ref,
       control_ref: control_ref,
       last_tick: start_ms,
       frame_count: 0,
       start_ms: start_ms
     }}
  end

  defp schedule_elixir_frame_tick do
    Process.send_after(self(), :elixir_frame_tick, @tick_ms)
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
        Logger.error("[Events.Game] #{inspect(component)}.on_ready/1 failed: #{inspect(result)}")
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

  # ── インフォ: UI アクション ──────────────────────────────────────

  @impl true
  def handle_info({:ui_action, action}, state) when is_binary(action) do
    new_state =
      case action do
        "__save__" ->
          Logger.info("[PERSIST] save ignored (local persistence disabled; network TBD)")
          state

        "__load__" ->
          Logger.info("[PERSIST] load ignored (local persistence disabled; network TBD)")
          state

        "__load_confirm__" ->
          Logger.info("[PERSIST] load confirm ignored (local persistence disabled; network TBD)")
          state

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
    # 入力の正規化・配信のみ行う。NIF 反映は maybe_set_input_and_broadcast で一本化する。

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

  # ── インフォ: 生入力イベント（Rust → LocalUserComponent）──

  def handle_info({:raw_key, key, key_state}, state)
      when is_atom(key) and key_state in [:pressed, :released] do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:raw_key, key, key_state}, context)
    {:noreply, state}
  end

  def handle_info({:raw_mouse_motion, dx, dy}, state) when is_number(dx) and is_number(dy) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:mouse_delta, dx * 1.0, dy * 1.0}, context)
    {:noreply, state}
  end

  def handle_info(:focus_lost, state) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components(:focus_lost, context)
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

  # ── インフォ: キー押下（LocalUserComponent が raw_key から生成）───────────

  def handle_info({:key_pressed, key}, state) when is_atom(key) do
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:key_pressed, key}, context)
    {:noreply, state}
  end

  # 終了要求（Device.Keyboard 等が __quit__ 受け取り時に送信。Content コールバックを経由）
  def handle_info(:quit_requested, _state) do
    content = current_content()

    if function_exported?(content, :on_quit_requested, 0) do
      content.on_quit_requested()
    else
      System.stop(0)
    end
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
    # 初回数フレームでログ（フレーム受信の確認用）
    if state.frame_count < 3 do
      Logger.info(
        "[Events.Game] frame_events received frame_count=#{state.frame_count} room=#{state.room_id}"
      )
    end

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

  # `:main` のローカル駆動（ゲーム用 NIF ループの代替）
  def handle_info(:elixir_frame_tick, %{room_id: :main} = state) do
    schedule_elixir_frame_tick()

    case handle_frame_events_main([], state, false) do
      {:noreply, new_state} -> {:noreply, new_state}
    end
  end

  def handle_info(:elixir_frame_tick, state), do: {:noreply, state}

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
    runner_result = runner && GenServer.call(runner, :current)

    opts = %{
      events: events,
      state: state,
      throttled?: throttled?,
      now: now,
      elapsed: elapsed,
      content: content,
      physics_scenes: physics_scenes,
      runner: runner
    }

    handle_frame_events_main_dispatch(runner_result, opts)
  end

  defp handle_frame_events_main_dispatch(nil, %{state: state, now: now}) do
    if state.frame_count < 5,
      do: Logger.warning("[Events.Game] runner=nil (flow_runner unavailable)")

    {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}
  end

  defp handle_frame_events_main_dispatch(:empty, %{state: state, now: now}) do
    if state.frame_count < 5, do: Logger.warning("[Events.Game] scene stack empty")
    {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}
  end

  defp handle_frame_events_main_dispatch(
         {:ok, %{scene_type: scene_type, state: scene_state}},
         %{
           events: events,
           state: state,
           throttled?: throttled?,
           now: now,
           elapsed: elapsed,
           content: content,
           runner: runner
         } = opts
       ) do
    context = build_context(state, now, elapsed, runner)

    Enum.each(events, &dispatch_frame_event_to_components(&1, context))

    result = content.scene_update(scene_type, context, scene_state)
    {new_scene_state, _opts} = extract_state_and_opts(result)
    GenServer.call(runner, {:update_current, fn _ -> new_scene_state end})

    # process_transition は state を変更せず返すのみ。副作用（GenServer.call による push/replace/pop）のみ行う。
    _state = process_transition(result, state, now, content, runner)

    Process.put(:frame_injection, %{})

    maybe_set_input_and_broadcast(
      state,
      scene_type,
      opts.physics_scenes,
      if(throttled?, do: [], else: events),
      context
    )

    # gameplay に必要な注入は throttled 時でも維持する。
    dispatch_nif_sync_to_components(context)
    apply_frame_injection(state)

    unless throttled? do
      apply_frame_noncritical_side_effects(state, scene_type, opts)
    end

    {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}
  end

  # 重い処理（ネットワーク publish / 診断キャッシュ）は遅延時にスキップ可能。
  defp apply_frame_noncritical_side_effects(state, scene_type, opts) do
    maybe_publish_zenoh_frame(state)
    Diagnostics.maybe_log_and_cache(state, scene_type, opts.elapsed, opts.content, opts.runner)
  end

  defp apply_frame_injection(state) do
    injection = Process.get(:frame_injection, %{})

    if map_size(injection) > 0 do
      do_apply_frame_injection(state, injection)
    end
  end

  defp do_apply_frame_injection(state, injection) do
    case Content.FrameEncoder.encode_injection_map(injection) do
      {:ok, frame_binary} ->
        apply_frame_injection_binary(state, frame_binary)

      {:error, reason} ->
        Logger.error(
          "[FrameEncoder] encode_injection_map failed (skipping frame injection): #{inspect(reason)}"
        )
    end
  end

  defp apply_frame_injection_binary(_state, _frame_binary) do
    # ゲーム用 NIF へのフレーム注入は撤去済み。描画は Render.on_nif_sync → FrameBroadcaster 経路。
    :ok
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

    Enum.each(Contents.ComponentList.components(), fn component ->
      if function_exported?(component, callback, arity) do
        apply(component, callback, args)
      end
    end)
  end

  defp maybe_set_input_and_broadcast(state, scene_type, physics_scenes, events, context) do
    if scene_type in physics_scenes do
      local_mod =
        Contents.ComponentList.local_user_input_module() || Contents.LocalUserComponent

      {dx, dy} = local_mod.get_move_vector(state.room_id)
      maybe_set_player_input_direct(state.world_ref, dx, dy)

      run_component_physics_callbacks(context)

      unless events == [], do: Core.EventBus.broadcast(events)
    end

    :ok
  end

  defp flow_runner(state), do: current_content().flow_runner(state.room_id)

  # P3: Zenoh 経由でフレームをリモートクライアントへ配信。
  # Contents.FrameBroadcaster が zenoh_enabled 時のみ Process.put(:zenoh_frame) を設定する。
  # contents は network に依存するが、テスト等で network がロードされない構成では
  # Code.ensure_loaded?/1 が false、または Process.whereis/1 が nil となり publish はスキップされ実害は小さい。
  defp maybe_publish_zenoh_frame(state) do
    debug_first_frames = state.frame_count < 5

    case Process.get(:zenoh_frame) do
      {room_id, frame_binary} when is_binary(frame_binary) ->
        Process.delete(:zenoh_frame)
        maybe_publish_zenoh_frame_when_available(room_id, frame_binary, state, debug_first_frames)

      _ ->
        maybe_publish_zenoh_frame_log_no_frame(state, debug_first_frames)
    end
  end

  defp maybe_publish_zenoh_frame_when_available(room_id, frame_binary, state, debug_first_frames) do
    zenoh_available? =
      Code.ensure_loaded?(Network.ZenohBridge) and Process.whereis(Network.ZenohBridge)

    if zenoh_available? do
      maybe_publish_zenoh_frame_log_publish(room_id, frame_binary, state, debug_first_frames)
      Network.ZenohBridge.publish_frame(room_id, frame_binary)
    else
      maybe_publish_zenoh_frame_log_unavailable(state, debug_first_frames)
    end
  end

  defp maybe_publish_zenoh_frame_log_publish(room_id, frame_binary, state, debug_first_frames) do
    if debug_first_frames or rem(state.frame_count, 60) == 0 do
      Logger.info(
        "[Zenoh] publishing frame room=#{room_id} size=#{byte_size(frame_binary)} frame_count=#{state.frame_count}"
      )
    end
  end

  defp maybe_publish_zenoh_frame_log_unavailable(state, debug_first_frames) do
    if debug_first_frames or rem(state.frame_count, 120) == 0 do
      Logger.warning("[Zenoh] ZenohBridge not available, skipping publish (debug)")
    end
  end

  defp maybe_publish_zenoh_frame_log_no_frame(state, debug_first_frames) do
    if debug_first_frames or rem(state.frame_count, 120) == 0 do
      Logger.warning("[Zenoh] no zenoh_frame in process frame_count=#{state.frame_count} (debug)")
    end

    :ok
  end

  defp build_context(state, now, elapsed, runner) do
    control_ref = state.control_ref
    content = current_content()

    # R-P2: dt = 1 フレームあたりの秒数。contents が damage_this_frame 計算に利用。
    dt = @tick_ms / 1000.0

    base = %{
      room_id: state.room_id,
      tick_ms: @tick_ms,
      dt: dt,
      world_ref: state.world_ref,
      now: now,
      elapsed: elapsed,
      frame_count: state.frame_count,
      start_ms: state.start_ms,
      push_scene: fn scene_type, init_arg ->
        if runner do
          _ = control_ref
          GenServer.call(runner, {:push, scene_type, init_arg})
        else
          :ok
        end
      end,
      pop_scene: fn ->
        _ = control_ref
        if runner, do: GenServer.call(runner, :pop), else: :ok
      end,
      replace_scene: fn scene_type, init_arg ->
        if runner, do: GenServer.call(runner, {:replace, scene_type, init_arg}), else: :ok
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

    GenServer.call(runner, :pop)
    state
  end

  defp process_transition(
         {:transition, {:push, scene_type, init_arg}, _},
         state,
         _now,
         _content,
         runner
       ) do
    GenServer.call(runner, {:push, scene_type, init_arg})
    state
  end

  defp process_transition(
         {:transition, {:replace, scene_type, init_arg}, _},
         state,
         now,
         content,
         runner
       ) do
    elapsed = now - state.start_ms

    init_arg =
      Diagnostics.build_replace_init_arg(
        scene_type,
        init_arg,
        elapsed,
        content,
        runner
      )

    GenServer.call(runner, {:replace, scene_type, init_arg})
    state
  end

  defp process_transition(_, state, _, _, _), do: state

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp current_content, do: Core.Config.current()

  defp maybe_set_player_input_direct(_world_ref, _dx, _dy), do: :ok
end
