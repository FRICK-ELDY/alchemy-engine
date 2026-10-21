defmodule Core.ConfigTickTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.get_env(:server, :tick_hz)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:server, :tick_hz)
      else
        Application.put_env(:server, :tick_hz, previous)
      end
    end)

    :ok
  end

  test "tick_hz defaults to 20" do
    Application.delete_env(:server, :tick_hz)
    assert Core.Config.tick_hz() == 20
    assert Core.Config.tick_ms() == 50
  end

  test "tick_hz accepts allowed values" do
    for hz <- [10, 20, 30, 60] do
      Application.put_env(:server, :tick_hz, hz)
      assert Core.Config.tick_hz() == hz
      assert Core.Config.tick_ms() == div(1000, hz)
    end
  end

  test "tick_hz falls back on invalid values" do
    Application.put_env(:server, :tick_hz, 15)
    assert Core.Config.tick_hz() == 20
    assert Core.Config.tick_ms() == 50
  end
end
