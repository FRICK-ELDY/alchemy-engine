defmodule Network.UDP do
  @moduledoc """
  `:gen_udp` による UDP トランスポートサーバー。

  クライアント（別 OS プロセス・別ノード）が UDP で接続し、
  ゲーム入力を送信してフレームイベントを受信できる。

  ## 接続フロー

      クライアント                   Network.UDP
          |                               |
          |--- JOIN(seq=1, "room_a") ---->|  register_room + セッション登録
          |<-- JOIN_ACK(seq=1, "room_a") -|
          |                               |
          |--- INPUT(seq=2, dx, dy) ----->|  GameEvents に :move_input を送信
          |<-- FRAME(seq=N, events) ------|  GameEvents からの :frame_events を転送
          |                               |
          |--- LEAVE(seq=M, "room_a") --->|  セッション削除
          |                               |

  ## セッション管理

  クライアントは `{ip, port}` で識別される。
  同一アドレスからの JOIN で既存セッションは上書きされる。

  ## パケット形式

  `Network.UDP.Protocol` を参照。

  ## 設定

      config :network, Network.UDP,
        port: 4001   # デフォルト: 4001

  実行時に変更する場合は `config/runtime.exs` で `GAME_NETWORK_UDP_PORT` を設定する。

  ## 受け入れ基準（フェーズ3）

  - 異なる OS プロセスから同一ルームに 2 プレイヤーが参加できる
  - ルームのクラッシュが他のルームに影響しない
  - localhost でのフレームイベント配信レイテンシ < 5ms
  """

  use GenServer
  require Logger

  alias Alchemy.Render.RenderFrame
  alias Network.UDP.Protocol

  @default_port 4001

  @type client_key :: {:inet.ip_address(), :inet.port_number()}
  @type session :: %{room_id: String.t()}

  # ── 公開 API ────────────────────────────────────────────────────────

  @doc """
  UDP サーバーを起動する。

  ポート番号は `config :network, Network.UDP, port: N` から読み取る。
  `opts` に `port:` を渡すことで上書きできる（テスト用途など）。
  """
  def start_link(opts \\ []) do
    port =
      Keyword.get_lazy(opts, :port, fn ->
        Application.get_env(:network, __MODULE__, [])
        |> Keyword.get(:port, @default_port)
      end)

    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @doc """
  UDP サーバーが使用しているポート番号を返す。
  """
  @spec port() :: non_neg_integer()
  def port do
    GenServer.call(__MODULE__, :port)
  end

  @doc """
  現在接続中のクライアント一覧を返す。
  各エントリは `{{ip, port}, session}` のタプル。
  """
  @spec sessions() :: [{client_key(), session()}]
  def sessions do
    GenServer.call(__MODULE__, :sessions)
  end

  @doc """
  指定ルームに接続している全クライアントにフレームイベントを送信する。
  `GameEvents` から `{:frame_events, events}` を受け取ったときに呼ばれる想定。
  """
  @spec broadcast_frame(String.t(), binary() | RenderFrame.t()) :: :ok
  def broadcast_frame(room_id, %RenderFrame{} = render_frame) do
    broadcast_frame(room_id, RenderFrame.encode(render_frame))
  end

  def broadcast_frame(room_id, frame_payload) when is_binary(frame_payload) do
    GenServer.cast(__MODULE__, {:broadcast_frame, room_id, frame_payload})
  end

  # ── GenServer コールバック ───────────────────────────────────────────

  @impl true
  def init(port) do
    # reuseaddr: true — テスト時のポート再利用（クラッシュ後の即時再起動）を可能にする。
    # UDP には TCP の TIME_WAIT がないため本番環境でも副作用はない。
    case :gen_udp.open(port, [:binary, active: true, reuseaddr: true]) do
      {:ok, socket} ->
        actual_port =
          case port do
            0 ->
              case :inet.port(socket) do
                {:ok, p} -> p
                {:error, _} -> port
              end

            _ ->
              port
          end

        Logger.info("[Network.UDP] Listening on UDP port #{actual_port}")
        {:ok, %{socket: socket, port: actual_port, sessions: %{}, next_seq: 0}}

      {:error, reason} ->
        {:stop, {:udp_open_failed, reason}}
    end
  end

  @impl true
  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  def handle_call(:sessions, _from, state) do
    {:reply, Map.to_list(state.sessions), state}
  end

  @impl true
  def handle_cast({:broadcast_frame, room_id, frame_payload}, state) do
    {seq, new_state} = next_seq(state)

    case Protocol.encode({:frame, seq, frame_payload}) do
      {:ok, packet} ->
        state.sessions
        |> Enum.filter(fn {_key, session} -> session.room_id == room_id end)
        |> Enum.each(fn {{ip, port}, _session} ->
          :gen_udp.send(new_state.socket, ip, port, packet)
        end)

      {:error, reason} ->
        Logger.error(
          "[Network.UDP] Failed to encode frame for room=#{room_id}: #{inspect(reason)}"
        )
    end

    {:noreply, new_state}
  end

  # ── UDP パケット受信 ─────────────────────────────────────────────────

  @impl true
  def handle_info({:udp, _socket, ip, port, data}, state) do
    client = {ip, port}

    new_state =
      case Protocol.decode(data) do
        {:ok, packet} ->
          handle_packet(packet, client, state)

        {:error, :invalid_packet} ->
          Logger.warning("[Network.UDP] Invalid packet from #{inspect(client)}")
          state
      end

    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :gen_udp.close(state.socket)
  end

  # ── パケットハンドラ ─────────────────────────────────────────────────

  defp handle_packet({:join, seq, room_id}, client, state) do
    case Network.Local.register_room(room_id) do
      :ok ->
        session = %{room_id: room_id}
        new_sessions = Map.put(state.sessions, client, session)
        Logger.info("[Network.UDP] Client #{inspect(client)} joined room=#{room_id}")

        {:ok, ack} = Protocol.encode({:join_ack, seq, room_id})
        {ip, port} = client
        :gen_udp.send(state.socket, ip, port, ack)

        %{state | sessions: new_sessions}

      {:error, reason} ->
        Logger.warning(
          "[Network.UDP] register_room failed for room=#{room_id}: #{inspect(reason)}"
        )

        {:ok, err_packet} = Protocol.encode({:error, seq, "register_failed"})
        {ip, port} = client
        :gen_udp.send(state.socket, ip, port, err_packet)

        state
    end
  end

  defp handle_packet({:leave, _seq, room_id}, client, state) do
    Logger.info("[Network.UDP] Client #{inspect(client)} left room=#{room_id}")
    %{state | sessions: Map.delete(state.sessions, client)}
  end

  defp handle_packet({:input, _seq, dx, dy}, client, state) do
    case Map.get(state.sessions, client) do
      nil ->
        Logger.warning("[Network.UDP] Input from unknown client #{inspect(client)}")

      %{room_id: room_id} ->
        case Core.RoomRegistry.get_loop(room_id) do
          {:ok, pid} ->
            send(pid, {:move_input, dx, dy})

          :error ->
            Logger.warning("[Network.UDP] Room #{room_id} not found for input")
        end
    end

    state
  end

  defp handle_packet({:action, _seq, name}, client, state) do
    case Map.get(state.sessions, client) do
      nil ->
        Logger.warning("[Network.UDP] Action from unknown client #{inspect(client)}")

      %{room_id: room_id} ->
        case Core.RoomRegistry.get_loop(room_id) do
          {:ok, pid} ->
            send(pid, {:ui_action, name})

          :error ->
            Logger.warning("[Network.UDP] Room #{room_id} not found for action")
        end
    end

    state
  end

  defp handle_packet({:ping, seq}, client, state) do
    ts = System.system_time(:millisecond)
    {:ok, pong} = Protocol.encode({:pong, seq, ts})
    {ip, port} = client
    :gen_udp.send(state.socket, ip, port, pong)
    state
  end

  defp handle_packet(packet, client, state) do
    Logger.debug(
      "[Network.UDP] Unhandled packet #{inspect(elem(packet, 0))} from #{inspect(client)}"
    )

    state
  end

  # ── ユーティリティ ───────────────────────────────────────────────────

  # 単調増加するシーケンス番号を発行する。
  # 32bit でラップアラウンドし、クライアント側での重複排除・順序保証に使用する。
  defp next_seq(%{next_seq: seq} = state) do
    new_seq = rem(seq + 1, 0x100000000)
    {seq, %{state | next_seq: new_seq}}
  end
end
