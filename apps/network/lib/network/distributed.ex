defmodule Network.Distributed do
  @moduledoc """
  複数ノード間でのルーム管理。

  libcluster によりクラスタが形成されている場合、ルームを任意のノードに配置し、
  ノード間で broadcast をルーティングする。

  ## 単一ノード時
  `Node.list() == []` の場合は `Network.Local` に委譲し、既存の挙動を維持する。

  ## 複数ノード時
  - `open_room/1`: ルームが未存在ならローカルノードで作成。既に他ノードにあれば
    `{:error, :already_started}` を返す（分散検索による重複検知。`Network.Local` のローカル重複とは別の意図）。
  - `broadcast/2`: ルームが配置されているノードを検索し、そのノードの `Network.Local.broadcast/2` を RPC で呼ぶ。
  - `list_rooms/0`: クラスタ全ノードのルームを集約して返す。
  """

  @type room_id :: String.t() | atom()
  @type event :: term()

  # ── 公開 API（Network モジュールから委譲される）───────────────────────

  @doc """
  ルームを起動する。

  単一ノードの場合は `Network.Local.open_room/1` に委譲。
  複数ノードの場合は、ルームが未存在ならローカルノードで作成する。
  """
  @spec open_room(room_id()) :: {:ok, pid()} | {:error, term()}
  def open_room(room_id) do
    if clustered?() do
      open_room_clustered(room_id)
    else
      Network.Local.open_room(room_id)
    end
  end

  @doc """
  ルームを停止する。

  ルームが配置されているノードの `Network.Local.close_room/1` を呼ぶ。
  """
  @spec close_room(room_id()) :: :ok | {:error, term()}
  def close_room(room_id) do
    if clustered?() do
      close_room_clustered(room_id)
    else
      Network.Local.close_room(room_id)
    end
  end

  @doc """
  ルームを接続テーブルに登録する。`Network.Local.register_room/1` に委譲。
  """
  @spec register_room(room_id()) :: :ok
  def register_room(room_id) do
    Network.Local.register_room(room_id)
  end

  @doc """
  ルームの登録を解除する。`Network.Local.unregister_room/1` に委譲。
  """
  @spec unregister_room(room_id()) :: :ok
  def unregister_room(room_id) do
    Network.Local.unregister_room(room_id)
  end

  @doc """
  2 つのルームを双方向に接続する。

  分散時は両ルームが同一ノードにある必要がある。異なるノードにある場合は
  `{:error, :rooms_on_different_nodes}` を返す。
  """
  @spec connect_rooms(room_id(), room_id()) :: :ok | {:error, term()}
  def connect_rooms(room_a, room_b) do
    if clustered?() do
      connect_rooms_clustered(room_a, room_b)
    else
      Network.Local.connect_rooms(room_a, room_b)
    end
  end

  @doc """
  接続を解除する。`Network.Local.disconnect_rooms/2` に委譲。
  """
  @spec disconnect_rooms(room_id(), room_id()) :: :ok
  def disconnect_rooms(room_a, room_b) do
    Network.Local.disconnect_rooms(room_a, room_b)
  end

  @doc """
  指定ルームとその接続先にイベントをブロードキャストする。

  分散時はルームが配置されているノードの `Network.Local.broadcast/2` を RPC で呼ぶ。
  """
  @spec broadcast(room_id(), event()) :: :ok | {:error, :room_not_found}
  def broadcast(room_id, event) do
    if clustered?() do
      broadcast_clustered(room_id, event)
    else
      Network.Local.broadcast(room_id, event)
    end
  end

  @doc """
  クラスタ全体で起動中のルーム一覧を返す。

  単一ノードの場合は `Network.Local.list_rooms/0` に委譲。
  """
  @spec list_rooms() :: [room_id()]
  def list_rooms do
    if clustered?() do
      list_rooms_clustered()
    else
      Network.Local.list_rooms()
    end
  end

  @doc """
  2 つのルームが接続されているか。`Network.Local.connected?/2` に委譲。

  分散時は両ルームが同一ノードにある場合のみ判定可能。
  異なるノードにある場合は `false` を返す。
  """
  @spec connected?(room_id(), room_id()) :: boolean()
  def connected?(room_a, room_b) do
    if clustered?() do
      connected_clustered?(room_a, room_b)
    else
      Network.Local.connected?(room_a, room_b)
    end
  end

  # ── クラスタ検知 ────────────────────────────────────────────────────

  defp clustered? do
    Node.list() != []
  end

  defp cluster_nodes do
    [node() | Node.list()]
  end

  # ── 分散時の実装 ─────────────────────────────────────────────────────

  defp open_room_clustered(room_id) do
    case find_room_node(room_id) do
      {_node, _} ->
        {:error, :already_started}

      nil ->
        Network.Local.open_room(room_id)
    end
  end

  defp close_room_clustered(room_id) do
    case find_room_node(room_id) do
      {target_node, ^room_id} when target_node == node() ->
        Network.Local.close_room(room_id)

      {target_node, ^room_id} ->
        case :rpc.call(target_node, Network.Local, :close_room, [room_id]) do
          :ok -> :ok
          {:error, _} = err -> err
          {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp connect_rooms_clustered(room_a, room_b) do
    case {find_room_node(room_a), find_room_node(room_b)} do
      {{node_a, _}, {node_b, _}} when node_a != node_b ->
        {:error, :rooms_on_different_nodes}

      {nil, _} ->
        {:error, {:room_not_found, room_a}}

      {_, nil} ->
        {:error, {:room_not_found, room_b}}

      {{target_node, _}, {target_node, _}} ->
        if target_node == node() do
          Network.Local.connect_rooms(room_a, room_b)
        else
          case :rpc.call(target_node, Network.Local, :connect_rooms, [room_a, room_b]) do
            :ok -> :ok
            {:error, _} = err -> err
            {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
          end
        end
    end
  end

  defp broadcast_clustered(room_id, event) do
    case find_room_node(room_id) do
      {target_node, ^room_id} when target_node == node() ->
        Network.Local.broadcast(room_id, event)

      {target_node, ^room_id} ->
        case :rpc.call(target_node, Network.Local, :broadcast, [room_id, event]) do
          result when result in [:ok, {:error, :room_not_found}] -> result
          {:badrpc, _} -> {:error, :room_not_found}
        end

      nil ->
        {:error, :room_not_found}
    end
  end

  defp list_rooms_clustered do
    cluster_nodes()
    |> Enum.flat_map(fn n ->
      if n == node() do
        Network.Local.list_rooms()
      else
        case :rpc.call(n, Network.Local, :list_rooms, []) do
          rooms when is_list(rooms) -> rooms
          _ -> []
        end
      end
    end)
    |> Enum.uniq()
  end

  defp connected_clustered?(room_a, room_b) do
    case {find_room_node(room_a), find_room_node(room_b)} do
      {{node_a, _}, {node_b, _}} when node_a != node_b ->
        false

      {{target_node, _}, {target_node, _}} ->
        if target_node == node() do
          Network.Local.connected?(room_a, room_b)
        else
          case :rpc.call(target_node, Network.Local, :connected?, [room_a, room_b]) do
            result when is_boolean(result) -> result
            _ -> false
          end
        end

      _ ->
        false
    end
  end

  # ルームが存在するノードを返す。{node, room_id} または nil
  # 呼び出しごとに全ノードへ RPC を行う。将来は :global レジストリや永続的な配置テーブルで
  # キャッシュする余地あり。
  defp find_room_node(room_id) do
    Enum.find_value(cluster_nodes(), fn n ->
      rooms =
        if n == node() do
          Network.Local.list_rooms()
        else
          case :rpc.call(n, Network.Local, :list_rooms, []) do
            r when is_list(r) -> r
            _ -> []
          end
        end

      if room_id in rooms, do: {n, room_id}, else: nil
    end)
  end
end
