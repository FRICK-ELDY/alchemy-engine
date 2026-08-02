defmodule Contents.FrameBroadcasterTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Contents.FrameBroadcaster

  setup do
    previous = Application.get_env(:contents, :zenoh_frame_publish)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:contents, :zenoh_frame_publish)
      else
        Application.put_env(:contents, :zenoh_frame_publish, previous)
      end

      Process.delete(:zenoh_frame)
    end)

    Process.delete(:zenoh_frame)
    :ok
  end

  test "MFA 未設定時は Process.put しない" do
    Application.put_env(:contents, :zenoh_frame_publish, nil)
    assert :ok = FrameBroadcaster.put("room-a", <<1, 2, 3>>)
    assert Process.get(:zenoh_frame) == nil
  end

  test "MFA 設定時は Process.put する" do
    Application.put_env(
      :contents,
      :zenoh_frame_publish,
      {__MODULE__.StubPublisher, :publish_frame, []}
    )

    frame = <<9, 8, 7>>
    assert :ok = FrameBroadcaster.put("room-b", frame)
    assert Process.get(:zenoh_frame) == {"room-b", frame}
  end

  defmodule StubPublisher do
    def publish_frame(_room_id, _frame_binary), do: :ok
  end
end
