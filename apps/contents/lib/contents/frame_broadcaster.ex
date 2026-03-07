defmodule Contents.FrameBroadcaster do
  @moduledoc """
  Zenoh フレーム配信用のユーティリティ。

  RenderComponent が `put/2` を呼び、`zenoh_enabled` 時のみ
  `Process.put(:zenoh_frame, ...)` を設定する。
  無効時は 60Hz の Process.put をスキップして負荷を抑える。
  """

  @doc """
  room_id と frame_binary を Zenoh 配信用に渡す。
  `config :network, :zenoh_enabled, true` のときのみ有効。
  """
  def put(room_id, frame_binary) when is_binary(frame_binary) do
    if Application.get_env(:network, :zenoh_enabled, false) do
      Process.put(:zenoh_frame, {room_id, frame_binary})
    end

    :ok
  end
end
