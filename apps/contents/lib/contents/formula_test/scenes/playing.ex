defmodule Content.FormulaTest.Scenes.Playing do
  @moduledoc """
  FormulaTest のプレイ中シーン。

  起動時に FormulaGraph を複数パターン実行し、Elixir→Rust→Elixir の
  フローが正しく動作することを検証する。結果は state に格納し、RenderComponent で表示。
  """
  @behaviour Contents.SceneBehaviour

  alias Core.FormulaGraph

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    results = run_formula_tests()
    {:ok, %{formula_results: results, hud_visible: true, cursor_grab_request: :no_change}}
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
    graph = %FormulaGraph{
      nodes: [
        %{id: :n1, op: :input, params: %{name: "player_x"}},
        %{id: :n2, op: :input, params: %{name: "player_y"}},
        %{id: :n3, op: :add, params: %{}},
        %{id: :n4, op: :output, params: %{}}
      ],
      edges: [
        {:n1, :n3, :a},
        {:n2, :n3, :b},
        {:n3, :n4, :value}
      ],
      outputs: [:n4]
    }

    case FormulaGraph.run(graph, %{"player_x" => 1.0, "player_y" => 2.0}) do
      {:ok, {[3.0], _}} -> {:ok, "player_x + player_y (1+2)", 3.0}
      {:ok, {outputs, _}} -> {:ok, "player_x + player_y", inspect(outputs)}
      {:error, reason, detail} -> {:error, "player_x + player_y", "#{reason} #{inspect(detail)}"}
    end
  end

  defp test_constants do
    graph = %FormulaGraph{
      nodes: [
        %{id: :a, op: :int, params: %{value: 10}},
        %{id: :b, op: :int, params: %{value: 3}},
        %{id: :sum, op: :add, params: %{}},
        %{id: :out, op: :output, params: %{}}
      ],
      edges: [
        {:a, :sum, :a},
        {:b, :sum, :b},
        {:sum, :out, :value}
      ],
      outputs: [:out]
    }

    case FormulaGraph.run(graph, %{}) do
      {:ok, {[13], _}} -> {:ok, "10 + 3", 13}
      {:ok, {outputs, _}} -> {:ok, "10 + 3", inspect(outputs)}
      {:error, reason, detail} -> {:error, "10 + 3", "#{reason} #{inspect(detail)}"}
    end
  end

  defp test_comparison do
    graph = %FormulaGraph{
      nodes: [
        %{id: :a, op: :input, params: %{name: "a"}},
        %{id: :b, op: :input, params: %{name: "b"}},
        %{id: :cmp, op: :lt, params: %{}},
        %{id: :out, op: :output, params: %{}}
      ],
      edges: [
        {:a, :cmp, :a},
        {:b, :cmp, :b},
        {:cmp, :out, :value}
      ],
      outputs: [:out]
    }

    case FormulaGraph.run(graph, %{"a" => 1.0, "b" => 2.0}) do
      {:ok, {[true], _}} -> {:ok, "lt(1.0, 2.0)", true}
      {:ok, {outputs, _}} -> {:ok, "lt(1.0, 2.0)", inspect(outputs)}
      {:error, reason, detail} -> {:error, "lt(1.0, 2.0)", "#{reason} #{inspect(detail)}"}
    end
  end

  defp test_store do
    graph = %FormulaGraph{
      nodes: [
        %{id: :r, op: :read_store, params: %{key: "score"}},
        %{id: :one, op: :int, params: %{value: 1}},
        %{id: :sum, op: :add, params: %{}},
        %{id: :w, op: :write_store, params: %{key: "score"}},
        %{id: :r2, op: :read_store, params: %{key: "score"}},
        %{id: :out, op: :output, params: %{}}
      ],
      edges: [
        {:r, :sum, :a},
        {:one, :sum, :b},
        {:sum, :w, :value},
        {:w, :r2, :after},
        {:r2, :out, :value}
      ],
      outputs: [:out]
    }

    case FormulaGraph.run(graph, %{}, %{"score" => 0}) do
      {:ok, {[1], store_list}} ->
        if {"score", 1} in store_list do
          {:ok, "read_store/write_store (0->1)", 1}
        else
          {:ok, "read_store/write_store", inspect(store_list)}
        end

      {:ok, {outputs, store_list}} ->
        {:ok, "read_store/write_store", "out=#{inspect(outputs)} store=#{inspect(store_list)}"}

      {:error, reason, detail} ->
        {:error, "read_store/write_store", "#{reason} #{inspect(detail)}"}
    end
  end

  defp test_multiple_outputs do
    graph = %FormulaGraph{
      nodes: [
        %{id: :a, op: :input, params: %{name: "x"}},
        %{id: :b, op: :input, params: %{name: "y"}},
        %{id: :add, op: :add, params: %{}},
        %{id: :sub, op: :sub, params: %{}},
        %{id: :o1, op: :output, params: %{}},
        %{id: :o2, op: :output, params: %{}}
      ],
      edges: [
        {:a, :add, :a},
        {:b, :add, :b},
        {:a, :sub, :a},
        {:b, :sub, :b},
        {:add, :o1, :value},
        {:sub, :o2, :value}
      ],
      outputs: [:o1, :o2]
    }

    case FormulaGraph.run(graph, %{"x" => 2.0, "y" => 3.0}) do
      {:ok, {[5.0, -1.0], _}} -> {:ok, "x+y, x-y (2,3)", [5.0, -1.0]}
      {:ok, {outputs, _}} -> {:ok, "x+y, x-y", inspect(outputs)}
      {:error, reason, detail} -> {:error, "x+y, x-y", "#{reason} #{inspect(detail)}"}
    end
  end
end
