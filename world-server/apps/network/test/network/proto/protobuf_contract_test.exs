defmodule Network.Proto.ProtobufContractTest do
  @moduledoc false
  use ExUnit.Case, async: true

  describe "Zenoh 主要経路の protobuf 契約（encode → decode）" do
    test "Movement" do
      msg = %Alchemy.Input.Movement{dx: 0.25, dy: -0.75}
      bin = Alchemy.Input.Movement.encode(msg)
      assert byte_size(bin) > 0

      assert %Alchemy.Input.Movement{dx: dx, dy: dy} = Alchemy.Input.Movement.decode(bin)
      assert_in_delta dx, 0.25, 1.0e-5
      assert_in_delta dy, -0.75, 1.0e-5
    end

    test "Action" do
      msg = %Alchemy.Input.Action{name: "pause"}
      bin = Alchemy.Input.Action.encode(msg)
      assert byte_size(bin) > 0

      assert %Alchemy.Input.Action{name: "pause"} = Alchemy.Input.Action.decode(bin)
    end

    test "ClientInfo" do
      msg = %Alchemy.Client.ClientInfo{os: "win32", arch: "x86_64", family: "windows"}
      bin = Alchemy.Client.ClientInfo.encode(msg)
      assert byte_size(bin) > 0

      assert %Alchemy.Client.ClientInfo{os: "win32", arch: "x86_64", family: "windows"} =
               Alchemy.Client.ClientInfo.decode(bin)
    end

    test "FrameInjection（Vec2f 付き）" do
      msg = %Alchemy.Frame.FrameInjection{
        player_input: %Alchemy.Frame.Vec2f{x: 1.0, y: 2.0}
      }

      bin = Alchemy.Frame.FrameInjection.encode(msg)
      assert byte_size(bin) > 0

      decoded = Alchemy.Frame.FrameInjection.decode(bin)
      assert %Alchemy.Frame.Vec2f{x: 1.0, y: 2.0} = decoded.player_input
    end
  end
end
