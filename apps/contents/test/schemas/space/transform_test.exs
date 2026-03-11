defmodule Schemas.Space.TransformTest do
  use ExUnit.Case, async: true
  alias Schemas.Category.Space.Transform

  describe "new/0" do
    test "returns default transform structure" do
      t = Transform.new()
      assert t.position == {0.0, 0.0, 0.0}
      assert t.rotation == {0.0, 0.0, 0.0, 1.0}
      assert t.scale == {1.0, 1.0, 1.0}
    end
  end
end
