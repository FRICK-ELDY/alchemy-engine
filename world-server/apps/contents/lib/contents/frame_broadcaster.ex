defmodule Contents.FrameBroadcaster do
  @moduledoc """
  Zenoh フレーム配信用のユーティリティ。

  RenderComponent が `put/2` を呼び、`config :contents, :zenoh_frame_publish` が
  設定されているときのみ `Process.put(:zenoh_frame, ...)` を設定する。
  無効時は 60Hz の Process.put をスキップして負荷を抑える。

  実際の publish は `Contents.Events.Game` が同 MFA 経由で行う（network への
  コンパイル時依存はない。FormulaStore の `:formula_store_broadcast` と同型）。
  """

  @doc """
  room_id と frame_binary を Zenoh 配信用に渡す。
  `config :contents, :zenoh_frame_publish` が非 nil のときのみ有効。
  """
  def put(room_id, frame_binary) when is_binary(frame_binary) do
    if Application.get_env(:contents, :zenoh_frame_publish) do
      Process.put(:zenoh_frame, {room_id, frame_binary})
    end

    :ok
  end
end
