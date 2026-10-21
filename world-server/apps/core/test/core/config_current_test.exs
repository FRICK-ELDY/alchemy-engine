defmodule Core.ConfigCurrentTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.get_env(:server, :current)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:server, :current)
      else
        Application.put_env(:server, :current, previous)
      end
    end)

    :ok
  end

  test "current/0 は config :server, :current を返す" do
    Application.put_env(:server, :current, Content.CanvasTest)
    assert Core.Config.current() == Content.CanvasTest
  end

  test "current/0 は未設定時に raise する（コンテンツ名フォールバックなし）" do
    Application.delete_env(:server, :current)

    assert_raise RuntimeError, ~r/config :server, :current is required/, fn ->
      Core.Config.current()
    end
  end
end
