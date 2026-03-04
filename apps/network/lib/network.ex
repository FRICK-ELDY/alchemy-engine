defmodule Network do
  @moduledoc """
  クライアント間・サーバー間通信モジュール。

  ## 実装済みサブモジュール

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
  新しいルームを起動する。`Network.Local.open_room/1` の委譲。
  """
  defdelegate open_room(room_id), to: Network.Local

  @doc """
  既に起動済みのルームプロセスを接続テーブルに登録する。
  `Network.Local.register_room/1` の委譲。
  """
  defdelegate register_room(room_id), to: Network.Local

  @doc """
  接続テーブルからルームの登録を解除する（プロセスは停止しない）。
  `Network.Local.unregister_room/1` の委譲。
  """
  defdelegate unregister_room(room_id), to: Network.Local

  @doc """
  ルームを停止する。`Network.Local.close_room/1` の委譲。
  """
  defdelegate close_room(room_id), to: Network.Local

  @doc """
  2 つのルームを双方向に接続する。`Network.Local.connect_rooms/2` の委譲。
  """
  defdelegate connect_rooms(room_a, room_b), to: Network.Local

  @doc """
  接続を解除する。`Network.Local.disconnect_rooms/2` の委譲。
  """
  defdelegate disconnect_rooms(room_a, room_b), to: Network.Local

  @doc """
  指定ルームとその接続先にイベントをブロードキャストする。
  `Network.Local.broadcast/2` の委譲。
  """
  defdelegate broadcast(room_id, event), to: Network.Local

  @doc """
  起動中のルーム一覧を返す。`Network.Local.list_rooms/0` の委譲。
  """
  defdelegate list_rooms(), to: Network.Local

  @doc """
  2 つのルームが接続されているかどうかを返す。`Network.Local.connected?/2` の委譲。
  """
  defdelegate connected?(room_a, room_b), to: Network.Local

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
