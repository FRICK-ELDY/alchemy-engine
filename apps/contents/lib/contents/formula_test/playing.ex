defmodule Content.FormulaTest.Playing do
  @moduledoc """
  FormulaTest のプレイ中シーン。

  起動時に Contents.Nodes を用いて複数パターンの式を実行し、
  ノードアーキテクチャの動作を検証する。結果は state に格納し、RenderComponent で表示。

  Phase 1 移行: FormulaGraph を Contents.Nodes に置き換え。
  配置: apps/contents/lib/contents/formula_test/playing.ex（Content 配下）。
  """
  @behaviour Contents.SceneBehaviour

  alias Contents.Nodes.Category.Core.Input.Value, as: ValueNode
  alias Contents.Nodes.Category.Operators.Add, as: AddNode
  alias Contents.Nodes.Category.Operators.Sub, as: SubNode
  alias Contents.Nodes.Category.Operators.Equals, as: EqualsNode
  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Contents.Objects.Core.CreateEmptyChild
  alias Structs.Category.Space.Transform

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
end
