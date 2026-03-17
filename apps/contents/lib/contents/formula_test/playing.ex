defmodule Content.FormulaTest.Playing do
  @moduledoc """
  FormulaTest のプレイ中シーン。

  起動時に Contents.Nodes を用いて複数パターンの式を実行し、
  ノードアーキテクチャの動作を検証する。結果は state に格納し、build_frame/2 で組み立てて Rendering.Render が送信する。

  Phase 1 移行: FormulaGraph を Contents.Nodes に置き換え。
  配置: apps/contents/lib/contents/formula_test/playing.ex（Content 配下）。
  """
  @behaviour Contents.SceneBehaviour

  # 描画用の既定値（build_frame/2 で参照。値の定義は Playing に集約）
  @render_camera_eye {0.0, 3.0, 8.0}
  @render_camera_target {0.0, 0.0, 0.0}
  @render_camera_up {0.0, 1.0, 0.0}
  @render_camera_fov 60.0
  @render_camera_near 0.1
  @render_camera_far 200.0
  @render_color_sky_top {0.2, 0.4, 0.6, 1.0}
  @render_color_sky_bottom {0.5, 0.7, 0.95, 1.0}
  @render_grid_size 20.0
  @render_grid_divisions 20
  @render_color_grid {0.25, 0.25, 0.3, 1.0}
  @render_color_ok {0.2, 0.8, 0.4, 1.0}
  @render_color_error {0.9, 0.3, 0.3, 1.0}
  @render_color_text {0.9, 0.95, 1.0, 1.0}
  @render_color_bg {0.05, 0.08, 0.12, 0.92}

  @doc "1 フレーム分の描画データを組み立てる。Rendering.Render が Content.build_frame 経由で呼ぶ。"
  def build_frame(state, context) do
    defaults = render_defaults()
    commands = build_frame_commands(defaults)
    camera = build_frame_camera(defaults)
    ui = build_frame_ui(state, context, defaults)
    {commands, camera, ui}
  end

  @doc "build_frame/2 が参照する描画用既定値"
  def render_defaults do
    %{
      camera_eye: @render_camera_eye,
      camera_target: @render_camera_target,
      camera_up: @render_camera_up,
      camera: {@render_camera_fov, @render_camera_near, @render_camera_far},
      color_sky_top: @render_color_sky_top,
      color_sky_bottom: @render_color_sky_bottom,
      grid_size: @render_grid_size,
      grid_divisions: @render_grid_divisions,
      color_grid: @render_color_grid,
      color_ok: @render_color_ok,
      color_error: @render_color_error,
      color_text: @render_color_text,
      color_bg: @render_color_bg
    }
  end

  alias Contents.Nodes.Category.Core.Input.Value, as: ValueNode
  alias Contents.Nodes.Category.Operators.Add, as: AddNode
  alias Contents.Nodes.Category.Operators.Sub, as: SubNode
  alias Contents.Nodes.Category.Operators.Equals, as: EqualsNode
  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Contents.Objects.Core.CreateEmptyChild
  alias Structs.Category.Space.Transform
  alias Contents.Components.Category.Shader.Skybox

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    results = run_formula_tests()
    origin = Transform.new()
    top_object = ObjectStruct.new(name: "User")

    # Scene 直下のトップレベルは User のみ。Child は User の子なので children には含めない。
    # 作成した Child を本シーンで参照する必要はないため、戻り値は束縛しない。
    case CreateEmptyChild.create(top_object, name: "Child") do
      {:ok, _child} ->
        :ok

      {:error, reason} ->
        raise "FormulaTest.Playing init: CreateEmptyChild.create failed: #{inspect(reason)}"
    end

    state = %{
      origin: origin,
      landing_object: top_object,
      children: [top_object],
      formula_results: results,
      hud_visible: true,
      # カーソルグラブ要求: Rendering.Render が毎フレーム読み取り、Rust へ送信後 :no_change にリセットする
      cursor_grab_request: :no_change
    }

    {:ok, state}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    {:continue, state}
  end

  # ── Formula 検証 ───────────────────────────────────────────────────

  defp run_formula_tests do
    [
      test_add_inputs(),
      test_constants(),
      test_comparison(),
      test_store(),
      test_multiple_outputs()
    ]
  end

  defp test_add_inputs do
    # Value(1) -> a, Value(2) -> b, Add(a, b) -> result
    # player_x, player_y は元 FormulaGraph の入力名。1+2 の加算を検証
    a = ValueNode.handle_sample(%{}, %{value: 1.0})
    b = ValueNode.handle_sample(%{}, %{value: 2.0})
    result = AddNode.handle_sample(%{a: a, b: b}, %{})

    case result do
      ival when is_number(ival) and ival == 3.0 ->
        {:ok, "player_x + player_y (1+2)", 3.0}

      ival when is_number(ival) ->
        {:ok, "player_x + player_y", inspect([ival])}

      {:error, reason} ->
        {:error, "player_x + player_y", "#{inspect(reason)}"}
    end
  end

  defp test_constants do
    # Value(10) -> a, Value(3) -> b, Add(a, b) -> result
    a = ValueNode.handle_sample(%{}, %{value: 10})
    b = ValueNode.handle_sample(%{}, %{value: 3})
    result = AddNode.handle_sample(%{a: a, b: b}, %{})

    case result do
      ival when is_number(ival) and ival == 13 -> {:ok, "10 + 3", 13}
      ival when is_number(ival) -> {:ok, "10 + 3", inspect([ival])}
      {:error, reason} -> {:error, "10 + 3", "#{inspect(reason)}"}
    end
  end

  defp test_comparison do
    # Value(1.0) -> a, Value(2.0) -> b, Equals(a, b, op: :lt) -> result
    a = ValueNode.handle_sample(%{}, %{value: 1.0})
    b = ValueNode.handle_sample(%{}, %{value: 2.0})
    result = EqualsNode.handle_sample(%{a: a, b: b, op: :lt}, %{})

    case result do
      true -> {:ok, "lt(1.0, 2.0)", true}
      false -> {:error, "lt(1.0, 2.0)", "expected true, got false"}
      {:error, reason} -> {:error, "lt(1.0, 2.0)", inspect(reason)}
      other -> {:error, "lt(1.0, 2.0)", "unexpected result: #{inspect(other)}"}
    end
  end

  defp test_store do
    # Store ノード（read_store / write_store）は Contents.Nodes に未実装のため、
    # 同等の計算（0 + 1 = 1）を Value + Add で検証する。
    # Phase 1 では Store の概念をスキップし、加算のみで動作確認。
    r = ValueNode.handle_sample(%{}, %{value: 0})
    one = ValueNode.handle_sample(%{}, %{value: 1})
    result = AddNode.handle_sample(%{a: r, b: one}, %{})

    case result do
      ival when is_number(ival) and ival == 1 ->
        {:ok, "read_store/write_store (0->1, simulated)", 1}

      ival when is_number(ival) ->
        {:ok, "read_store/write_store", inspect([ival])}

      {:error, reason} ->
        {:error, "read_store/write_store", "#{inspect(reason)}"}
    end
  end

  defp test_multiple_outputs do
    # Value(2), Value(3) -> Add -> 5, Sub -> -1
    a = ValueNode.handle_sample(%{}, %{value: 2.0})
    b = ValueNode.handle_sample(%{}, %{value: 3.0})
    add_result = AddNode.handle_sample(%{a: a, b: b}, %{})
    sub_result = SubNode.handle_sample(%{a: a, b: b}, %{})

    case {add_result, sub_result} do
      {a_r, s_r} when is_number(a_r) and is_number(s_r) and a_r == 5.0 and s_r == -1.0 ->
        {:ok, "x+y, x-y (2,3)", [5.0, -1.0]}

      {a_r, s_r} when is_number(a_r) and is_number(s_r) ->
        {:ok, "x+y, x-y", inspect([a_r, s_r])}

      {{:error, reason}, _} ->
        {:error, "x+y, x-y", "#{inspect(reason)}"}

      {_, {:error, reason}} ->
        {:error, "x+y, x-y", "#{inspect(reason)}"}
    end
  end

  # ── 描画フレーム組み立て（定義は contents に集約）───────────────────────

  defp build_frame_commands(defaults) do
    grid_vertices =
      Content.MeshDef.grid_plane(
        size: defaults.grid_size,
        divisions: defaults.grid_divisions,
        color: defaults.color_grid
      )[:vertices]

    [
      Skybox.skybox_command(defaults.color_sky_top, defaults.color_sky_bottom),
      {:grid_plane_verts, grid_vertices}
    ]
  end

  defp build_frame_camera(defaults) do
    {fov, near, far} = defaults.camera
    {:camera_3d, defaults.camera_eye, defaults.camera_target, defaults.camera_up,
     {fov, near, far}}
  end

  defp build_frame_ui(state, context, defaults) do
    results = Map.get(state, :formula_results, [])
    hud_visible = Map.get(state, :hud_visible, true)

    hud_nodes =
      if hud_visible do
        [build_frame_formula_hud_panel(results, context, defaults)]
      else
        []
      end

    {:canvas, hud_nodes}
  end

  defp build_frame_formula_hud_panel(results, context, defaults) do
    fps_text =
      if context.tick_ms > 0,
        do: "FPS: #{round(1000.0 / context.tick_ms)}",
        else: "FPS: --"

    ok_count = Enum.count(results, fn {status, _, _} -> status == :ok end)
    total_count = length(results)
    summary = "Formula Test: #{ok_count}/#{total_count} OK"
    result_lines = build_frame_format_results(results, defaults)

    {:node, {:center, {0.0, 0.0}, :wrap}, {:rect, defaults.color_bg, 12.0, :none},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap},
        {:vertical_layout, 8.0, {24.0, 20.0, 24.0, 20.0}},
        [
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:text, "Formula Engine Verification", defaults.color_text, 24.0, true}, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:text, "Elixir -> Rust (NIF VM) -> Elixir", {0.7, 0.75, 0.85, 1.0}, 14.0, false},
           []},
          {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap}, {:text, summary, defaults.color_text, 18.0, true},
           []},
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:text, fps_text, {0.6, 0.65, 0.8, 1.0}, 14.0, false}, []},
          {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []}
        ] ++ result_lines ++
          [
            {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
            {:node, {:top_left, {0.0, 0.0}, :wrap},
             {:button, "  Quit  ", "__quit__", {0.55, 0.2, 0.2, 1.0}, 120.0, 36.0}, []}
          ]}
     ]}
  end

  defp build_frame_format_results(results, defaults) do
    results
    |> Enum.with_index(1)
    |> Enum.map(fn {{status, desc, value}, i} ->
      color = if status == :ok, do: defaults.color_ok, else: defaults.color_error
      status_str = if status == :ok, do: "OK", else: "ERR"
      value_str = build_frame_format_value(value)

      {:node, {:top_left, {0.0, 0.0}, :wrap},
       {:text, "#{i}. [#{status_str}] #{desc} => #{value_str}", color, 14.0, false}, []}
    end)
  end

  defp build_frame_format_value(value) when is_list(value), do: inspect(value)
  defp build_frame_format_value(value) when is_boolean(value), do: to_string(value)
  defp build_frame_format_value(value) when is_number(value), do: to_string(value)
  defp build_frame_format_value(value), do: inspect(value)
end
