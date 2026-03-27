defmodule Network.ZenohBridgeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  setup do
    if :ets.whereis(:client_info) == :undefined do
      :ets.new(:client_info, [:named_table, :public, :set, read_concurrency: true])
    end

    :ets.delete_all_objects(:client_info)
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
  end
end
