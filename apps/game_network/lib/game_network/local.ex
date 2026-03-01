defmodule GameNetwork.Local do
  @moduledoc """
  同一 BEAM ノード内でのローカルマルチルーム管理。

  2 つの `GameEngine.GameEvents` プロセスを接続し、
  イベントを相互にルーティングする。

  ## 目的
  - OTP 隔離の証明: ルーム A がクラッシュしてもルーム B が継続動作すること
  - 同時 60Hz 物理演算の実証: 2 ルームが独立して動作できること

  ## 使い方

      {:ok, _} = GameNetwork.Local.start_link()
      {:ok, pid_a} = GameNetwork.Local.open_room("room_a")
      {:ok, pid_b} = GameNetwork.Local.open_room("room_b")
      :ok = GameNetwork.Local.connect_rooms("room_a", "room_b")
      :ok = GameNetwork.Local.broadcast("room_a", {:chat, "hello"})
  """

  use GenServer
  require Logger

  @type room_id :: String.t() | atom()
  @type event :: term()

  # ── 公開 API ────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  新しいルームを起動する。

  `GameEngine.RoomSupervisor` 経由で `GameEngine.GameEvents` を起動し、
  ルーム ID を登録する。
  """
  @spec open_room(room_id()) :: {:ok, pid()} | {:error, term()}
  def open_room(room_id) do
    GenServer.call(__MODULE__, {:open_room, room_id})
  end

  @doc """
  ルームを停止する。
  """
  @spec close_room(room_id()) :: :ok | {:error, term()}
  def close_room(room_id) do
    GenServer.call(__MODULE__, {:close_room, room_id})
  end

  @doc """
  既に起動済みのルームプロセスを接続テーブルに登録する。

  `open_room/1` がプロセス起動と登録を一括で行うのに対し、
  この関数はプロセス起動を行わず登録のみを行う。
  外部 Supervisor で管理済みのプロセスを後から参加させる場合に使用する。

  既に登録済みの場合は何もせず `:ok` を返す（冪等操作）。
  """
  @spec register_room(room_id()) :: :ok
  def register_room(room_id) do
    GenServer.call(__MODULE__, {:register_room, room_id})
  end

  @doc """
  接続テーブルからルームの登録を解除する。

  `close_room/1` と異なり、プロセスの停止は行わず登録情報の削除のみを行う。
  登録されていない場合は何もせず `:ok` を返す（冪等操作）。

  ## 注意: 接続情報も同時に削除される

  このルームへの接続（他ルームの MapSet に含まれる参照）も削除される。
  つまり `register_room → connect_rooms → unregister_room → register_room` の
  再登録サイクルを行うと、接続は失われた状態になる。
  再登録後に再度 `connect_rooms/2` を呼ぶ必要がある。
  """
  @spec unregister_room(room_id()) :: :ok
  def unregister_room(room_id) do
    GenServer.call(__MODULE__, {:unregister_room, room_id})
  end

  @doc """
  2 つのルームを双方向に接続する。

  接続後、どちらかのルームに `broadcast/2` したイベントは
  もう一方のルームにも転送される。
  """
  @spec connect_rooms(room_id(), room_id()) :: :ok | {:error, term()}
  def connect_rooms(room_a, room_b) do
    GenServer.call(__MODULE__, {:connect_rooms, room_a, room_b})
  end

  @doc """
  接続を解除する。

  指定したルームが存在しない場合でも `:ok` を返す（冪等操作）。
  存在しないルームへの disconnect は無視される。
  """
  @spec disconnect_rooms(room_id(), room_id()) :: :ok
  def disconnect_rooms(room_a, room_b) do
    GenServer.call(__MODULE__, {:disconnect_rooms, room_a, room_b})
  end

  @doc """
  指定ルームとその接続先全てにイベントをブロードキャストする。

  送信先ルームの `GameEngine.GameEvents` プロセスに
  `{:network_event, from_room, event}` として届く。
  """
  @spec broadcast(room_id(), event()) :: :ok | {:error, :room_not_found}
  def broadcast(room_id, event) do
    GenServer.call(__MODULE__, {:broadcast, room_id, event})
  end

  @doc """
  現在起動中のルーム一覧を返す。
  """
  @spec list_rooms() :: [room_id()]
  def list_rooms do
    GenServer.call(__MODULE__, :list_rooms)
  end

  @doc """
  2 つのルームが接続されているかどうかを返す。
  """
  @spec connected?(room_id(), room_id()) :: boolean()
  def connected?(room_a, room_b) do
    GenServer.call(__MODULE__, {:connected?, room_a, room_b})
  end

  # ── GenServer コールバック ───────────────────────────────────────────

  @impl true
  def init(_opts) do
    # connections: %{room_id => MapSet.t(room_id)}
    {:ok, %{connections: %{}}}
  end

  @impl true
  def handle_call({:register_room, room_id}, _from, state) do
    {:reply, :ok, put_room(state, room_id)}
  end

  def handle_call({:unregister_room, room_id}, _from, state) do
    new_connections = remove_room_connections(state.connections, room_id)
    {:reply, :ok, %{state | connections: new_connections}}
  end

  def handle_call({:open_room, room_id}, _from, state) do
    case GameEngine.RoomSupervisor.start_room(room_id) do
      {:ok, pid} ->
        Logger.info("[GameNetwork.Local] Opened room #{inspect(room_id)} (pid=#{inspect(pid)})")
        {:reply, {:ok, pid}, put_room(state, room_id)}

      {:error, :already_started} = err ->
        {:reply, err, state}

      other ->
        {:reply, other, state}
    end
  end

  def handle_call({:close_room, room_id}, _from, state) do
    case GameEngine.RoomSupervisor.stop_room(room_id) do
      :ok ->
        new_connections = remove_room_connections(state.connections, room_id)
        Logger.info("[GameNetwork.Local] Closed room #{inspect(room_id)}")
        {:reply, :ok, %{state | connections: new_connections}}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:connect_rooms, room_a, room_b}, _from, state) do
    cond do
      not Map.has_key?(state.connections, room_a) ->
        {:reply, {:error, {:room_not_found, room_a}}, state}

      not Map.has_key?(state.connections, room_b) ->
        {:reply, {:error, {:room_not_found, room_b}}, state}

      true ->
        new_connections =
          state.connections
          |> Map.update!(room_a, &MapSet.put(&1, room_b))
          |> Map.update!(room_b, &MapSet.put(&1, room_a))

        Logger.info("[GameNetwork.Local] Connected #{inspect(room_a)} <-> #{inspect(room_b)}")
        {:reply, :ok, %{state | connections: new_connections}}
    end
  end

  def handle_call({:disconnect_rooms, room_a, room_b}, _from, state) do
    new_connections =
      state.connections
      |> update_if_exists(room_a, &MapSet.delete(&1, room_b))
      |> update_if_exists(room_b, &MapSet.delete(&1, room_a))

    Logger.info("[GameNetwork.Local] Disconnected #{inspect(room_a)} <-> #{inspect(room_b)}")
    {:reply, :ok, %{state | connections: new_connections}}
  end

  def handle_call({:broadcast, room_id, event}, _from, state) do
    case Map.fetch(state.connections, room_id) do
      :error ->
        {:reply, {:error, :room_not_found}, state}

      {:ok, peers} ->
        Enum.each(peers, fn peer_id ->
          deliver_event(peer_id, room_id, event)
        end)
        {:reply, :ok, state}
    end
  end

  def handle_call(:list_rooms, _from, state) do
    {:reply, Map.keys(state.connections), state}
  end

  def handle_call({:connected?, room_a, room_b}, _from, state) do
    result =
      case Map.fetch(state.connections, room_a) do
        {:ok, peers} -> MapSet.member?(peers, room_b)
        :error -> false
      end

    {:reply, result, state}
  end

  # ── プライベート ─────────────────────────────────────────────────────

  # ルームを接続テーブルに追加する（既存の場合は何もしない）
  defp put_room(state, room_id) do
    %{state | connections: Map.put_new(state.connections, room_id, MapSet.new())}
  end

  # キーが存在する場合のみ値を更新する。存在しない場合は何もしない。
  # Map.update/4 と異なり、キーが無くてもデフォルト値でエントリを作成しない。
  defp update_if_exists(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, val} -> Map.put(map, key, fun.(val))
      :error -> map
    end
  end

  # ルームが閉じられたとき、そのルームへの全接続を削除する
  defp remove_room_connections(connections, room_id) do
    peers = Map.get(connections, room_id, MapSet.new())

    connections
    |> Map.delete(room_id)
    |> Map.new(fn {id, set} ->
      if MapSet.member?(peers, id) do
        {id, MapSet.delete(set, room_id)}
      else
        {id, set}
      end
    end)
  end

  # 対象ルームの GameEvents プロセスにイベントを送信する
  defp deliver_event(room_id, from_room, event) do
    case GameEngine.RoomRegistry.get_loop(room_id) do
      {:ok, pid} ->
        send(pid, {:network_event, from_room, event})

      :error ->
        Logger.warning(
          "[GameNetwork.Local] deliver_event: room #{inspect(room_id)} not found"
        )
    end
  end
end
