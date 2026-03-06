defmodule Core.FormulaGraphTest do
  use ExUnit.Case, async: true

  alias Core.FormulaGraph

  describe "compile/1" do
    test "player_x + player_y のグラフをコンパイルして実行" do
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

      assert {:ok, _bytecode} = FormulaGraph.compile(graph)

      assert {:ok, {[3.0], _}} =
               FormulaGraph.run(graph, %{"player_x" => 1.0, "player_y" => 2.0})

      assert {:ok, {[x], _}} =
               FormulaGraph.run(graph, %{"player_x" => -1.0, "player_y" => 1.0})

      assert abs(x - 0.0) < 1.0e-6
    end

    test "定数と演算" do
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

      assert {:ok, {[13], _}} = FormulaGraph.run(graph, %{})
    end

    test "比較ノード (lt)" do
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

      assert {:ok, {[true], _}} = FormulaGraph.run(graph, %{"a" => 1.0, "b" => 2.0})
      assert {:ok, {[false], _}} = FormulaGraph.run(graph, %{"a" => 2.0, "b" => 1.0})
    end

    test "read_store / write_store ノード" do
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

      assert {:ok, {[1], store_list}} =
               FormulaGraph.run(graph, %{}, %{"score" => 0})

      assert {"score", 1} in store_list
    end

    test "複数出力" do
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

      assert {:ok, {[5.0, -1.0], _}} =
               FormulaGraph.run(graph, %{"x" => 2.0, "y" => 3.0})
    end

    test "循環参照でエラー" do
      graph = %FormulaGraph{
        nodes: [
          %{id: :a, op: :int, params: %{value: 1}},
          %{id: :b, op: :add, params: %{}},
          %{id: :out, op: :output, params: %{}}
        ],
        edges: [
          {:a, :b, :a},
          {:b, :b, :b},
          {:b, :out, :value}
        ],
        outputs: [:out]
      }

      assert {:error, :cycle_detected, nil} = FormulaGraph.compile(graph)
    end

    test "不正なノードでエラー" do
      graph = %FormulaGraph{
        nodes: [%{id: :bad, op: :unknown_op, params: %{}}],
        edges: [],
        outputs: []
      }

      assert {:error, :invalid_graph, {:validation_error, _}} = FormulaGraph.compile(graph)
    end

    test "存在しないノードを参照するエッジでエラー" do
      graph = %FormulaGraph{
        nodes: [
          %{id: :a, op: :int, params: %{value: 1}},
          %{id: :out, op: :output, params: %{}}
        ],
        edges: [{:nonexistent, :out, :value}],
        outputs: [:out]
      }

      assert {:error, :invalid_graph, {:unknown_node, :nonexistent}} =
               FormulaGraph.compile(graph)
    end

    test "二項演算の入力ポート未接続でエラー" do
      graph = %FormulaGraph{
        nodes: [
          %{id: :a, op: :int, params: %{value: 1}},
          %{id: :sum, op: :add, params: %{}},
          %{id: :out, op: :output, params: %{}}
        ],
        edges: [
          {:a, :sum, :a},
          {:sum, :out, :value}
        ],
        outputs: [:out]
      }

      assert {:error, :invalid_graph, {:missing_input, :sum, :b}} =
               FormulaGraph.compile(graph)
    end

    test "output ノードの入力未接続でエラー" do
      graph = %FormulaGraph{
        nodes: [
          %{id: :out, op: :output, params: %{}}
        ],
        edges: [],
        outputs: [:out]
      }

      assert {:error, :invalid_graph, {:missing_input, :out}} =
               FormulaGraph.compile(graph)
    end
  end
end
