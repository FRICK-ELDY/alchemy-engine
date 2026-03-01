defmodule GameNetwork do
  @moduledoc """
  クライアント間・サーバー間通信モジュール。

  ## 実装済みサブモジュール

  - `GameNetwork.Local` — 同一 BEAM ノード内でのローカルマルチルーム管理（フェーズ1）。
    OTP 隔離と並行 60Hz 物理演算を実証。
  - `GameNetwork.Channel` — Phoenix Channels / WebSocket トランスポート（フェーズ2）。
    `GameNetwork.Endpoint` (`/socket`) 経由でブラウザ等から接続できる。
    `"room:<room_id>"` トピックに join してゲームルームに参加する。

  ## 将来のサブモジュール（未実装）

  - `GameNetwork.UDP` — `:gen_udp` によるロックステップ同期（フェーズ3）
  """

  @doc """
  新しいルームを起動する。`GameNetwork.Local.open_room/1` の委譲。
  """
  defdelegate open_room(room_id), to: GameNetwork.Local

  @doc """
  既に起動済みのルームプロセスを接続テーブルに登録する。
  `GameNetwork.Local.register_room/1` の委譲。
  """
  defdelegate register_room(room_id), to: GameNetwork.Local

  @doc """
  接続テーブルからルームの登録を解除する（プロセスは停止しない）。
  `GameNetwork.Local.unregister_room/1` の委譲。
  """
  defdelegate unregister_room(room_id), to: GameNetwork.Local

  @doc """
  ルームを停止する。`GameNetwork.Local.close_room/1` の委譲。
  """
  defdelegate close_room(room_id), to: GameNetwork.Local

  @doc """
  2 つのルームを双方向に接続する。`GameNetwork.Local.connect_rooms/2` の委譲。
  """
  defdelegate connect_rooms(room_a, room_b), to: GameNetwork.Local

  @doc """
  接続を解除する。`GameNetwork.Local.disconnect_rooms/2` の委譲。
  """
  defdelegate disconnect_rooms(room_a, room_b), to: GameNetwork.Local

  @doc """
  指定ルームとその接続先にイベントをブロードキャストする。
  `GameNetwork.Local.broadcast/2` の委譲。
  """
  defdelegate broadcast(room_id, event), to: GameNetwork.Local

  @doc """
  起動中のルーム一覧を返す。`GameNetwork.Local.list_rooms/0` の委譲。
  """
  defdelegate list_rooms(), to: GameNetwork.Local

  @doc """
  2 つのルームが接続されているかどうかを返す。`GameNetwork.Local.connected?/2` の委譲。
  """
  defdelegate connected?(room_a, room_b), to: GameNetwork.Local
end
