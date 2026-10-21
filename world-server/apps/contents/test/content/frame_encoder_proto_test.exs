defmodule Contents.FrameEncoder.ProtoTest do
  use ExUnit.Case, async: true

  alias Contents.FrameEncoder.Proto

  test "pb_float は binary32 に量子化し、pb_double は仮数を保つ" do
    exact = 16_777_217.0

    assert Proto.pb_float(exact) == 16_777_216.0
    assert Proto.pb_double(exact) == exact
  end
end
