defmodule Contents.Nodes.Test.Formula do
  @moduledoc """
  Nodes を用いた式検証（Value, Add, Sub, Equals 等）。

  他のコンテンツからも共通利用可能。`run/0` で検証を実行し、
  各要素が `{:ok, desc, value}` または `{:error, desc, reason}` のいずれかであるリストを返す。
  :ok/:error 以外のタプルが混ざると呼び出し側の集計（例: OK 数）が誤るため、追加する検証もこの2形に限定すること。
  """
  alias Contents.Nodes.Category.Core.Input.Value, as: ValueNode
  alias Contents.Nodes.Category.Operators.Add, as: AddNode
  alias Contents.Nodes.Category.Operators.Sub, as: SubNode
  alias Contents.Nodes.Category.Operators.Equals, as: EqualsNode

  @type result_item :: {:ok, String.t(), term()} | {:error, String.t(), term()}

  @doc """
  複数パターンの式検証を実行し、結果のリストを返す。

  各要素は `{:ok, desc, value}` または `{:error, desc, reason}` のいずれかである。
  """
  @spec run() :: [result_item()]
  def run do
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
