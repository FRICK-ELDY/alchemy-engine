defmodule Network.ZenohBridgeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  setup do
    if :ets.whereis(:client_info) == :undefined do
      :ets.new(:client_info, [:named_table, :public, :set, read_concurrency: true])
    end

    :ets.delete_all_objects(:client_info)

    on_exit(fn ->
      Application.put_env(:network, :auth_required, false)
    end)

    :ok
  end

  describe "handle_info/2 client_info decode path" do
    test "valid protobuf payload is stored in ETS" do
      payload =
        Alchemy.Client.ClientInfo.encode(%Alchemy.Client.ClientInfo{
          os: "win32",
          arch: "x86_64",
          family: "windows"
        })

      sample = %Zenohex.Sample{
        key_expr: "contents/room/main/client/info",
        payload: payload,
        kind: :put
      }

      assert {:noreply, %{test_state: true}} =
               Network.ZenohBridge.handle_info(sample, %{test_state: true})

      assert [{{:main, :info}, info}] = :ets.lookup(:client_info, {:main, :info})
      assert info == %{os: "win32", arch: "x86_64", family: "windows"}
    end

    test "invalid payload is discarded and processing continues" do
      sample = %Zenohex.Sample{
        key_expr: "contents/room/main/client/info",
        payload: <<0xDE, 0xAD, 0xBE, 0xEF>>,
        kind: :put
      }

      assert {:noreply, %{test_state: true}} =
               Network.ZenohBridge.handle_info(sample, %{test_state: true})

      assert [] == :ets.lookup(:client_info, {:main, :info})
    end

    test "AUTH_REQUIRED 時は token なし client_info を拒否する" do
      Application.put_env(:network, :auth_required, true)

      payload =
        Alchemy.Client.ClientInfo.encode(%Alchemy.Client.ClientInfo{
          os: "win32",
          arch: "x86_64",
          family: "windows"
        })

      sample = %Zenohex.Sample{
        key_expr: "contents/room/main/client/info",
        payload: payload,
        kind: :put
      }

      assert {:noreply, _} = Network.ZenohBridge.handle_info(sample, %{})
      assert [] == :ets.lookup(:client_info, {:main, :info})
    end

    test "AUTH_REQUIRED 時は RoomToken 付き client_info を受け入れる" do
      Application.put_env(:network, :auth_required, true)
      {:ok, token} = Network.RoomToken.sign("main")

      protobuf =
        Alchemy.Client.ClientInfo.encode(%Alchemy.Client.ClientInfo{
          os: "linux",
          arch: "aarch64",
          family: "unix"
        })

      sample = %Zenohex.Sample{
        key_expr: "contents/room/main/client/info",
        payload: Network.RoomAuth.wrap_payload(token, protobuf),
        kind: :put
      }

      assert {:noreply, _} = Network.ZenohBridge.handle_info(sample, %{})
      assert [{{:main, :info}, info}] = :ets.lookup(:client_info, {:main, :info})
      assert info.os == "linux"
    end
  end
end
