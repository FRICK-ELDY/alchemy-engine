defmodule Network do
  @moduledoc """
  クライアント間・サーバー間通信モジュール。

  ## 実装済みサブモジュール

  - `Network.Distributed` — 複数ノード間でのルーム管理。libcluster によりクラスタ形成時は
    ノードをまたいだ open_room/broadcast をサポート。単一ノード時は `Network.Local` に委譲。
  - `Network.Local` — 同一 BEAM ノード内でのローカルマルチルーム管理（フェーズ1）。
    OTP 隔離と並行 60Hz 物理演算を実証。
  - `Network.Channel` — Phoenix Channels / WebSocket トランスポート（フェーズ2）。
    `Network.Endpoint` (`/socket`) 経由でブラウザ等から接続できる。
    `"room:<room_id>"` トピックに join してゲームルームに参加する。

  ## 実装済みサブモジュール（続き）

  - `Network.UDP` — `:gen_udp` による UDP トランスポート（フェーズ3）。
    デフォルトポート 4001 で待ち受け。クライアントは JOIN パケットでルームに参加し、
    INPUT/ACTION を送信してフレームイベントを受信する。
  """

  @doc """
  新しいルームを起動する。`Network.Distributed.open_room/1` の委譲。
  クラスタ形成時は分散配置をサポート。
  """
  defdelegate open_room(room_id), to: Network.Distributed

  @doc """
  既に起動済みのルームプロセスを接続テーブルに登録する。
  `Network.Distributed.register_room/1` の委譲。
  """
  defdelegate register_room(room_id), to: Network.Distributed

  @doc """
  接続テーブルからルームの登録を解除する（プロセスは停止しない）。
  `Network.Distributed.unregister_room/1` の委譲。
  """
  defdelegate unregister_room(room_id), to: Network.Distributed

  @doc """
  ルームを停止する。`Network.Distributed.close_room/1` の委譲。
  クラスタ形成時はルームが配置されているノードで close を実行する。
  """
  defdelegate close_room(room_id), to: Network.Distributed

  @doc """
  2 つのルームを双方向に接続する。`Network.Distributed.connect_rooms/2` の委譲。
  分散時は両ルームが同一ノードにある必要がある。
  """
  defdelegate connect_rooms(room_a, room_b), to: Network.Distributed

  @doc """
  接続を解除する。`Network.Distributed.disconnect_rooms/2` の委譲。
  """
  defdelegate disconnect_rooms(room_a, room_b), to: Network.Distributed

  @doc """
  指定ルームとその接続先にイベントをブロードキャストする。
  `Network.Distributed.broadcast/2` の委譲。
  クラスタ形成時はルームが配置されているノードに RPC で転送する。
  """
  defdelegate broadcast(room_id, event), to: Network.Distributed

  @doc """
  起動中のルーム一覧を返す。`Network.Distributed.list_rooms/0` の委譲。
  クラスタ形成時は全ノードのルームを集約する。
  """
  defdelegate list_rooms(), to: Network.Distributed

  @doc """
  2 つのルームが接続されているかどうかを返す。`Network.Distributed.connected?/2` の委譲。
  """
  defdelegate connected?(room_a, room_b), to: Network.Distributed

  @doc """
  UDP サーバーが使用しているポート番号を返す。`Network.UDP.port/0` の委譲。
  """
  defdelegate udp_port(), to: Network.UDP, as: :port

  @doc """
  UDP で接続中のクライアント一覧を返す。`Network.UDP.sessions/0` の委譲。
  """
  defdelegate udp_sessions(), to: Network.UDP, as: :sessions

  @doc """
  指定ルームに接続している UDP クライアント全員にフレームイベントを送信する。
  `Network.UDP.broadcast_frame/2` の委譲。

  WebSocket 向けのブロードキャストと区別するため `_udp` サフィックスを付けている。
  """
  defdelegate broadcast_frame_udp(room_id, events), to: Network.UDP, as: :broadcast_frame
end
