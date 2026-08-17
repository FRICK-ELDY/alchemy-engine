defmodule Contents.Components.Category.Network.Osc.ProtocolTest do
  use ExUnit.Case, async: true

  alias Contents.Components.Category.Network.Osc.Protocol

  describe "encode_message/2 + decode/1" do
    test "int / float / string / bool / nil をラウンドトリップする" do
      args = [42, 1.5, "hello", true, false, nil]

      assert {:ok, {:message, "/alchemy/test", decoded}} =
               Protocol.decode(Protocol.encode_message("/alchemy/test", args))

      assert hd(decoded) == 42
      assert_in_delta Enum.at(decoded, 1), 1.5, 0.0001
      assert Enum.at(decoded, 2) == "hello"
      assert Enum.at(decoded, 3) == true
      assert Enum.at(decoded, 4) == false
      assert Enum.at(decoded, 5) == nil
    end

    test "引数なしメッセージをデコードする" do
      bin = Protocol.encode_message("/ping", [])
      assert {:ok, {:message, "/ping", []}} = Protocol.decode(bin)
    end

    test "既知のパディング（/ping）" do
      bin = Protocol.encode_message("/ping", [])
      assert bin == "/ping\0\0\0,\0\0\0"
    end

    test "不正なバイナリは :invalid" do
      assert Protocol.decode(<<1, 2, 3>>) == {:error, :invalid}
    end
  end

  describe "encode_bundle/1 + decode/1" do
    test "複数メッセージをバンドルしてデコードする" do
      bin = Protocol.encode_bundle([{"/a", [1]}, {"/b", [2.0]}])
      assert {:ok, {:bundle, :immediate, elements}} = Protocol.decode(bin)
      assert [{:message, "/a", [1]}, {:message, "/b", [b]}] = elements
      assert_in_delta b, 2.0, 0.0001
    end
  end
end

defmodule Contents.Components.Category.Network.Osc.LoopbackTest do
  use ExUnit.Case, async: true

  alias Contents.Components.Category.Network.Osc.Field
  alias Contents.Components.Category.Network.Osc.Protocol
  alias Contents.Components.Category.Network.Osc.Receiver
  alias Contents.Components.Category.Network.Osc.Sender
  alias Contents.Components.Category.Network.Osc.Value

  setup do
    {:ok, receiver} = Receiver.start_link(port: 0, access_reason: "test receiver")
    on_exit(fn -> if Process.alive?(receiver), do: Receiver.stop(receiver) end)

    fields = Receiver.fields(receiver)
    assert fields.is_listening
    assert fields.port > 0

    {:ok, receiver: receiver, port: fields.port}
  end

  test "LittleOSC 相当の /1/push1 float を Value に反映する", %{receiver: receiver, port: port} do
    {:ok, value} = Value.start_link(handler: receiver, path: "/1/push1", value: 0.0)
    on_exit(fn -> if Process.alive?(value), do: Value.stop(value) end)

    wait_until(fn -> match?([_ | _], :sys.get_state(receiver).bindings["/1/push1"] || []) end)

    {:ok, sock} = :gen_udp.open(0, [:binary, active: false])
    on_exit(fn -> :gen_udp.close(sock) end)

    packet = Protocol.encode_message("/1/push1", [1.0])
    :ok = :gen_udp.send(sock, {127, 0, 0, 1}, port, packet)

    wait_until(fn ->
      got = Value.get(value)
      is_float(got) and abs(got - 1.0) < 0.0001
    end)

    packet0 = Protocol.encode_message("/1/push1", [0.0])
    :ok = :gen_udp.send(sock, {127, 0, 0, 1}, port, packet0)

    wait_until(fn ->
      got = Value.get(value)
      is_float(got) and abs(got - 0.0) < 0.0001
    end)

    last = Receiver.last_packet(receiver)
    assert last.path == "/1/push1"
    assert_in_delta hd(last.args), 0.0, 0.0001
  end

  test "Receiver が外部 UDP の OSC を Value に反映する", %{receiver: receiver, port: port} do
    {:ok, value} = Value.start_link(handler: receiver, path: "/alchemy/in", value: 0.0)
    on_exit(fn -> if Process.alive?(value), do: Value.stop(value) end)

    wait_until(fn -> match?([_ | _], :sys.get_state(receiver).bindings["/alchemy/in"] || []) end)

    {:ok, sock} = :gen_udp.open(0, [:binary, active: false])
    on_exit(fn -> :gen_udp.close(sock) end)

    packet = Protocol.encode_message("/alchemy/in", [1.25])
    :ok = :gen_udp.send(sock, {127, 0, 0, 1}, port, packet)

    wait_until(fn ->
      got = Value.get(value)
      is_float(got) and abs(got - 1.25) < 0.0001
    end)
  end

  test "Field が Agent へ OSC 値を書き込む", %{receiver: receiver, port: port} do
    {:ok, agent} = Agent.start_link(fn -> 0.0 end)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

    {:ok, field} =
      Field.start_link(handler: receiver, path: "/alchemy/field", field: {:agent, agent})

    on_exit(fn -> if Process.alive?(field), do: Field.stop(field) end)

    wait_until(fn ->
      match?([_ | _], :sys.get_state(receiver).bindings["/alchemy/field"] || [])
    end)

    {:ok, sock} = :gen_udp.open(0, [:binary, active: false])
    on_exit(fn -> :gen_udp.close(sock) end)

    packet = Protocol.encode_message("/alchemy/field", [7])
    :ok = :gen_udp.send(sock, {127, 0, 0, 1}, port, packet)

    wait_until(fn -> Field.get(field) == 7 end)
    assert Agent.get(agent, & &1) == 7
  end

  test "Sender と Receiver のループバックで Value がエコーされる", %{receiver: receiver, port: port} do
    {:ok, sender} =
      Sender.start_link(
        url: "osc://127.0.0.1:#{port}",
        auto_resend_interval: 0.0,
        access_reason: "test sender"
      )

    on_exit(fn -> if Process.alive?(sender), do: Sender.stop(sender) end)
    assert Sender.fields(sender).is_sending

    {:ok, echo} = Value.start_link(handler: receiver, path: "/alchemy/out", value: 0.0)
    on_exit(fn -> if Process.alive?(echo), do: Value.stop(echo) end)

    wait_until(fn -> match?([_ | _], :sys.get_state(receiver).bindings["/alchemy/out"] || []) end)

    {:ok, out} = Value.start_link(handler: sender, path: "/alchemy/out", value: 0.0)
    on_exit(fn -> if Process.alive?(out), do: Value.stop(out) end)

    :ok = Value.set(out, 0.75)

    wait_until(fn ->
      got = Value.get(echo)
      is_float(got) and abs(got - 0.75) < 0.0001
    end)
  end

  test "複数引数 OSC は ArgumentIndex で取り出す", %{receiver: receiver, port: port} do
    {:ok, yaw} =
      Value.start_link(handler: receiver, path: "/osc/rotation", argument_index: 1, value: 0.0)

    on_exit(fn -> if Process.alive?(yaw), do: Value.stop(yaw) end)

    wait_until(fn ->
      match?([_ | _], :sys.get_state(receiver).bindings["/osc/rotation"] || [])
    end)

    {:ok, sock} = :gen_udp.open(0, [:binary, active: false])
    on_exit(fn -> :gen_udp.close(sock) end)

    packet = Protocol.encode_message("/osc/rotation", [90, 180, 0])
    :ok = :gen_udp.send(sock, {127, 0, 0, 1}, port, packet)

    wait_until(fn -> Value.get(yaw) == 180 end)
  end

  test "new/1 が Resonite 互換フィールドを持つ" do
    recv = Receiver.new(port: 3001, access_reason: "host access")
    assert recv.port == 3001
    assert recv.access_reason == "host access"
    assert recv.enabled
    refute recv.is_listening

    send = Sender.new(url: "osc://127.0.0.1:3001", send_mode: :send_as_bundles)
    assert send.url == "osc://127.0.0.1:3001"
    assert send.send_mode == :send_as_bundles
    assert send.local_port == 0

    value = Value.new(path: "/foo", argument_index: 2, value: 1.0)
    assert value.path == "/foo"
    assert value.argument_index == 2
    assert value.value == 1.0

    field = Field.new(path: "/bar", field: nil)
    assert field.path == "/bar"
    assert field.field == nil
  end

  defp wait_until(fun, attempts \\ 50) do
    if fun.() do
      true
    else
      if attempts <= 0 do
        flunk("timeout waiting for OSC condition")
      else
        Process.sleep(10)
        wait_until(fun, attempts - 1)
      end
    end
  end
end
