defmodule Network.Proto.ProtobufContractTest do
  @moduledoc false
  use ExUnit.Case, async: true

  describe "Zenoh 主要経路の protobuf 契約（encode → decode）" do
    test "Movement" do
      msg = %Network.Proto.Movement{dx: 0.25, dy: -0.75}
      bin = Network.Proto.Movement.encode(msg)
      assert byte_size(bin) > 0

      assert %Network.Proto.Movement{dx: dx, dy: dy} = Network.Proto.Movement.decode(bin)
      assert_in_delta dx, 0.25, 1.0e-5
      assert_in_delta dy, -0.75, 1.0e-5
    end

    test "Action" do
      msg = %Network.Proto.Action{name: "pause"}
      bin = Network.Proto.Action.encode(msg)
      assert byte_size(bin) > 0

      assert %Network.Proto.Action{name: "pause"} = Network.Proto.Action.decode(bin)
    end

    test "ClientInfo" do
      msg = %Network.Proto.ClientInfo{os: "win32", arch: "x86_64", family: "windows"}
      bin = Network.Proto.ClientInfo.encode(msg)
      assert byte_size(bin) > 0

      assert %Network.Proto.ClientInfo{os: "win32", arch: "x86_64", family: "windows"} =
               Network.Proto.ClientInfo.decode(bin)
    end

    test "FrameInjection（Vec2f 付き）" do
      msg = %Network.Proto.FrameInjection{
        player_input: %Network.Proto.Vec2f{x: 1.0, y: 2.0}
      }

      bin = Network.Proto.FrameInjection.encode(msg)
      assert byte_size(bin) > 0

      decoded = Network.Proto.FrameInjection.decode(bin)
      assert %Network.Proto.Vec2f{x: 1.0, y: 2.0} = decoded.player_input
    end
  end
end
