defmodule Network.Local.TestHelpers do
  @moduledoc """
  `Network.Local` のテスト専用ヘルパー。

  `Network.Local` 本体に Mix.env() 依存のコードを混入させず、
  テスト側からのみ参照する。

  ## 使い方

      :ok = Network.Local.TestHelpers.inject_room("room_a")
  """

  @doc """
  `Network.Local` の接続テーブルにルームを登録する。

  `open_room/1` は `Core.RoomSupervisor`（NIF 起動）を呼ぶため、
  テストでは代わりにこの関数でルームを登録する。

  `Network.Local.register_room/1` の公開 API を経由するため、
  内部メッセージ形式への直接依存がない。
  """
  @spec inject_room(term()) :: :ok
  def inject_room(room_id) do
    Network.Local.register_room(room_id)
  end

  @doc """
  `Network.Local` の接続テーブルからルームの登録を解除する。

  `inject_room/1` の逆操作。テスト終了時の `on_exit` クリーンアップで使用する。
  """
  @spec eject_room(term()) :: :ok
  def eject_room(room_id) do
    Network.Local.unregister_room(room_id)
  end
end
