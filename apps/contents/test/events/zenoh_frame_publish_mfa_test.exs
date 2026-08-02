defmodule Contents.Events.ZenohFramePublishMfaTest do
  @moduledoc """
  contents → network の MFA 注入（:zenoh_frame_publish）を検証する。
  Events.Game の private 関数は直接呼べないため、設定の解決契約と
  FrameBroadcaster → Process 辞書の経路を確認する。
  """
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

  test "MFA は {mod, fun, []} 形式で apply(mod, fun, [room_id, frame]) できる" do
    Application.put_env(
      :contents,
      :zenoh_frame_publish,
      {__MODULE__.Capture, :publish_frame, []}
    )

    :ets.new(__MODULE__.Capture, [:named_table, :public, :set])

    room_id = "mfa-room"
    frame = <<1, 2, 3, 4>>
    assert :ok = FrameBroadcaster.put(room_id, frame)
    assert Process.get(:zenoh_frame) == {room_id, frame}

    {mod, fun, []} = Application.get_env(:contents, :zenoh_frame_publish)
    {^room_id, ^frame} = Process.get(:zenoh_frame)
    Process.delete(:zenoh_frame)
    assert :ok = apply(mod, fun, [room_id, frame])
    assert :ets.lookup(__MODULE__.Capture, :last) == [{:last, {room_id, frame}}]
  end

  test "2 引数 fun も設定として受け付ける" do
    parent = self()

    Application.put_env(:contents, :zenoh_frame_publish, fn room_id, frame ->
      send(parent, {:published, room_id, frame})
      :ok
    end)

    fun = Application.get_env(:contents, :zenoh_frame_publish)
    assert is_function(fun, 2)
    assert :ok = fun.("r1", <<0>>)
    assert_receive {:published, "r1", <<0>>}
  end

  defmodule Capture do
    def publish_frame(room_id, frame_binary) do
      :ets.insert(__MODULE__, {:last, {room_id, frame_binary}})
      :ok
    end
  end
end
