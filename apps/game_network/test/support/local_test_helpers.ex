defmodule GameNetwork.Local.TestHelpers do
  @moduledoc """
  `GameNetwork.Local` のテスト専用ヘルパー。

  `GameNetwork.Local` 本体に Mix.env() 依存のコードを混入させず、
  テスト側からのみ参照する。

  ## 使い方

      :ok = GameNetwork.Local.TestHelpers.inject_room("room_a")
  """

  @doc """
  `GameNetwork.Local` の接続テーブルにルームを登録する。

  `open_room/1` は `GameEngine.RoomSupervisor`（NIF 起動）を呼ぶため、
  テストでは代わりにこの関数でルームを登録する。

  `GameNetwork.Local.register_room/1` の公開 API を経由するため、
  内部メッセージ形式への直接依存がない。
  """
  @spec inject_room(term()) :: :ok
  def inject_room(room_id) do
    GameNetwork.Local.register_room(room_id)
  end
end
