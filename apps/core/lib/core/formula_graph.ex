defmodule Core.FormulaGraph do
  @moduledoc """
   ProtoFlux/Logix 風の計算グラフ。Phase 3 で導入。

  Elixir でノードとエッジを定義し、バイトコードにコンパイルして実行する。

  ## ノード種別
  - `:input` - 外部入力。params: %{name: "player_x"}
  - `:output` - 出力。params: %{}。接続元の値を出力へ。
  - `:add`, `:sub`, `:mul`, `:div`, `:lt`, `:gt`, `:eq` - 二項演算。入力ポート :a, :b
  - `:int` - 定数整数。params: %{value: 10}
  - `:float` - 定数浮動小数。params: %{value: 1.0}
  - `:bool` - 定数真偽。params: %{value: true}
  - `:read_store` - Store 読み取り。params: %{key: "score"}
  - `:write_store` - Store 書き込み。params: %{key: "score"}。入力ポート :value
  - エッジのポート `:after` はデータなしの実行順序のみ指定（例: write_store の後に read_store を実行）

  ## 例
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

      FormulaGraph.compile(graph)
      # => {:ok, bytecode}

      FormulaGraph.run(graph, %{"player_x" => 1.0, "player_y" => 2.0})
      # => {:ok, {[3.0], []}}
  """

  defstruct nodes: [], edges: [], outputs: []

  @type node_id :: atom()
  @type graph_node :: %{
          required(:id) => node_id(),
          required(:op) => atom(),
          required(:params) => map()
        }
  @type edge :: {node_id(), node_id(), atom()}
  @type t :: %__MODULE__{
          nodes: [graph_node()],
          edges: [edge()],
          outputs: [node_id()]
        }

  alias Core.Formula

  @producer_ops [:input, :int, :float, :bool, :add, :sub, :mul, :div, :lt, :gt, :eq, :read_store]
  @sink_ops [:output, :write_store]
  @valid_ops @producer_ops ++ @sink_ops

  @doc """
  グラフをバイトコードにコンパイルする。

  ## 戻り値
  - `{:ok, bytecode}` - 成功
  - `{:error, reason, detail}` - 失敗（循環参照、未知ノード、ポート不足など）
  """
  @spec compile(t()) :: {:ok, binary()} | {:error, atom(), term()}
  def compile(%__MODULE__{nodes: nodes, edges: edges, outputs: outputs}) do
    with {:ok, node_map} <- validate_nodes(nodes),
         {:ok, incoming, outgoing} <- build_incoming(edges, node_map),
         {:ok, sorted} <- topological_sort(nodes, incoming, outgoing),
         {:ok, reg_map} <- assign_registers(sorted, node_map),
         {:ok, instructions} <- emit_instructions(sorted, node_map, reg_map, incoming, outputs) do
      {:ok, Formula.build(instructions)}
    end
  end

  @doc """
  グラフをコンパイルして実行する。

  inputs と store_values は Formula.run/3 と同様。
  """
  @spec run(t(), map(), map()) ::
          {:ok, {[term()], [{String.t(), term()}]}}
          | {:error, atom(), term()}
  def run(graph, inputs, store_values \\ %{}) do
    with {:ok, bytecode} <- compile(graph) do
      Formula.run(bytecode, inputs, store_values)
    end
  end

  # --- Validation ---

  defp validate_nodes(nodes) when not is_list(nodes),
    do: {:error, :invalid_graph, :nodes_not_list}

  defp validate_nodes(nodes) when nodes == [], do: {:error, :invalid_graph, :empty_nodes}

  defp validate_nodes(nodes) do
    node_map =
      for n <- nodes, into: %{} do
        cond do
          not is_map(n) -> raise "node must be map"
          not Map.has_key?(n, :id) -> raise "node must have :id"
          not Map.has_key?(n, :op) -> raise "node must have :op"
          n.op not in @valid_ops -> raise "unknown op: #{inspect(n.op)}"
          true -> {n.id, Map.put_new(n, :params, %{})}
        end
      end

    {:ok, node_map}
  rescue
    e in RuntimeError -> {:error, :invalid_graph, {:validation_error, e.message}}
  end

  defp build_incoming(edges, _node_map) when not is_list(edges) do
    {:error, :invalid_graph, :edges_not_list}
  end

  defp build_incoming(edges, node_map) do
    Enum.reduce_while(edges, {:ok, %{}, %{}}, fn {from, to, port}, {:ok, inc, out} ->
      cond do
        not Map.has_key?(node_map, from) ->
          {:halt, {:error, :invalid_graph, {:unknown_node, from}}}

        not Map.has_key?(node_map, to) ->
          {:halt, {:error, :invalid_graph, {:unknown_node, to}}}

        true ->
          inc_next = Map.update(inc, to, [{from, port}], fn list -> [{from, port} | list] end)
          out_next = Map.update(out, from, [to], fn list -> [to | list] end)
          {:cont, {:ok, inc_next, out_next}}
      end
    end)
  end

  # Kahn's algorithm for topological sort
  defp build_in_degree(node_ids, incoming) do
    Enum.reduce(node_ids, %{}, fn nid, acc ->
      deg = (incoming[nid] || []) |> length()
      Map.put(acc, nid, deg)
    end)
  end

  defp get_dependents(nid, outgoing) do
    Map.get(outgoing, nid, []) |> Enum.uniq()
  end

  defp topological_sort(nodes, incoming, outgoing) do
    node_ids = MapSet.new(nodes, & &1.id)
    in_degree = build_in_degree(node_ids, incoming)
    roots = Enum.filter(in_degree, fn {_, d} -> d == 0 end) |> Enum.map(&elem(&1, 0))
    kahn_loop(roots, in_degree, outgoing, node_ids, [], MapSet.new())
  end

  defp kahn_loop([], _in_degree, _outgoing, node_ids, result, result_set) do
    if MapSet.size(result_set) == MapSet.size(node_ids) do
      {:ok, Enum.reverse(result)}
    else
      {:error, :cycle_detected, nil}
    end
  end

  defp kahn_loop([nid | queue], in_degree, outgoing, node_ids, result, result_set) do
    dependents = get_dependents(nid, outgoing)

    deg_next =
      Enum.reduce(dependents, in_degree, fn dep, d ->
        Map.update(d, dep, 0, fn v -> max(0, v - 1) end)
      end)

    result_set_next = MapSet.put(result_set, nid)

    new_roots =
      for {n, 0} <- deg_next,
          not MapSet.member?(result_set_next, n),
          n not in queue,
          n != nid,
          do: n

    kahn_loop(
      queue ++ Enum.uniq(new_roots),
      deg_next,
      outgoing,
      node_ids,
      [nid | result],
      result_set_next
    )
  end

  # --- Register assignment ---
  defp assign_registers(sorted, node_map) do
    producers = Enum.filter(sorted, fn nid -> node_map[nid].op in @producer_ops end)
    reg_map = Enum.with_index(producers) |> Map.new(fn {nid, r} -> {nid, r} end)

    if map_size(reg_map) > 64,
      do: {:error, :too_many_registers, map_size(reg_map)},
      else: {:ok, reg_map}
  end

  # --- Instruction emission ---
  # Emit non-output nodes in topological order, then output nodes in outputs order
  defp emit_instructions(sorted, node_map, reg_map, incoming, outputs) do
    non_output = Enum.reject(sorted, fn nid -> node_map[nid].op == :output end)
    output_nids = Enum.filter(outputs, &Map.has_key?(node_map, &1))

    case emit_nodes(non_output, node_map, reg_map, incoming) do
      {:ok, instrs_non} ->
        case emit_nodes(output_nids, node_map, reg_map, incoming) do
          {:ok, instrs_output} -> {:ok, instrs_non ++ instrs_output}
          err -> err
        end

      err ->
        err
    end
  end

  defp emit_nodes(nids, node_map, reg_map, incoming) do
    Enum.reduce_while(nids, {:ok, []}, fn nid, {:ok, acc} ->
      case emit_node(node_map[nid], reg_map, incoming) do
        {:ok, instrs} -> {:cont, {:ok, acc ++ instrs}}
        {:error, _, _} = err -> {:halt, err}
      end
    end)
  end

  defp emit_node(node, reg_map, incoming) do
    op = node.op
    params = node.params
    nid = node.id
    dst = reg_map[nid]

    result =
      case op do
        :input ->
          name = Map.fetch!(params, :name) |> to_string()
          {:ok, [{:load_input, dst, name}]}

        :int ->
          v = Map.fetch!(params, :value)
          {:ok, [{:load_i32, dst, v}]}

        :float ->
          v = Map.fetch!(params, :value)
          {:ok, [{:load_f32, dst, int_to_float(v)}]}

        :bool ->
          v = Map.fetch!(params, :value)
          {:ok, [{:load_bool, dst, v}]}

        :read_store ->
          key = (params[:key] || params["key"]) |> to_string()
          {:ok, [{:read_store, dst, key}]}

        :add ->
          with {:ok, {ra, rb}} <- get_input_regs(nid, incoming, reg_map, [:a, :b]) do
            {:ok, [{:add, dst, ra, rb}]}
          end

        :sub ->
          with {:ok, {ra, rb}} <- get_input_regs(nid, incoming, reg_map, [:a, :b]) do
            {:ok, [{:sub, dst, ra, rb}]}
          end

        :mul ->
          with {:ok, {ra, rb}} <- get_input_regs(nid, incoming, reg_map, [:a, :b]) do
            {:ok, [{:mul, dst, ra, rb}]}
          end

        :div ->
          with {:ok, {ra, rb}} <- get_input_regs(nid, incoming, reg_map, [:a, :b]) do
            {:ok, [{:div, dst, ra, rb}]}
          end

        :lt ->
          with {:ok, {ra, rb}} <- get_input_regs(nid, incoming, reg_map, [:a, :b]) do
            {:ok, [{:lt, dst, ra, rb}]}
          end

        :gt ->
          with {:ok, {ra, rb}} <- get_input_regs(nid, incoming, reg_map, [:a, :b]) do
            {:ok, [{:gt, dst, ra, rb}]}
          end

        :eq ->
          with {:ok, {ra, rb}} <- get_input_regs(nid, incoming, reg_map, [:a, :b]) do
            {:ok, [{:eq, dst, ra, rb}]}
          end

        :output ->
          case get_data_input(nid, incoming, reg_map) do
            {:ok, src} -> {:ok, [{:store_output, src}]}
            err -> err
          end

        :write_store ->
          case get_data_input(nid, incoming, reg_map) do
            {:ok, src} ->
              key = (params[:key] || params["key"]) |> to_string()
              {:ok, [{:write_store, src, key}]}

            err ->
              err
          end
      end

    result
  end

  defp get_data_input(nid, incoming, reg_map) do
    in_edges = incoming[nid] || []
    value_edge = Enum.find(in_edges, fn {_, port} -> port == :value end)

    case value_edge do
      {from, :value} -> {:ok, reg_map[from]}
      nil -> {:error, :invalid_graph, {:missing_input, nid}}
    end
  end

  defp get_input_regs(nid, incoming, reg_map, ports) do
    in_edges = incoming[nid] || []

    regs =
      Enum.reduce_while(ports, {:ok, []}, fn port, {:ok, acc} ->
        edge = Enum.find(in_edges, fn {_, p} -> p == port end)

        case edge do
          {from, ^port} -> {:cont, {:ok, [reg_map[from] | acc]}}
          nil -> {:halt, {:error, :invalid_graph, {:missing_input, nid, port}}}
        end
      end)

    case regs do
      {:ok, list} -> {:ok, list |> Enum.reverse() |> List.to_tuple()}
      err -> err
    end
  end

  defp int_to_float(x) when is_integer(x), do: x / 1
  defp int_to_float(x), do: x
end
