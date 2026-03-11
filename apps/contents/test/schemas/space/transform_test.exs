defmodule Schemas.Space.TransformTest do
  use ExUnit.Case, async: true
  alias Schemas.Category.Space.Transform

  describe "euler_rad round-trip" do
    test "90 deg X rotation" do
      t = Transform.new()
      euler_in = {:math.pi() / 2, 0.0, 0.0}
      t2 = Transform.put_rotation_euler_rad(t, euler_in)
      euler_out = Transform.to_euler_rad(t2)
      assert_in_delta elem(euler_in, 0), elem(euler_out, 0), 1.0e-5
      assert_in_delta elem(euler_in, 1), elem(euler_out, 1), 1.0e-5
      assert_in_delta elem(euler_in, 2), elem(euler_out, 2), 1.0e-5
    end

    test "identity" do
      t = Transform.new()
      {x, y, z} = Transform.to_euler_rad(t)
      assert_in_delta 0.0, x, 1.0e-5
      assert_in_delta 0.0, y, 1.0e-5
      assert_in_delta 0.0, z, 1.0e-5
    end

    test "45 deg Y rotation" do
      t = Transform.new()
      euler_in = {0.0, :math.pi() / 4, 0.0}
      t2 = Transform.put_rotation_euler_rad(t, euler_in)
      euler_out = Transform.to_euler_rad(t2)
      assert_in_delta elem(euler_in, 0), elem(euler_out, 0), 1.0e-5
      assert_in_delta elem(euler_in, 1), elem(euler_out, 1), 1.0e-5
      assert_in_delta elem(euler_in, 2), elem(euler_out, 2), 1.0e-5
    end
  end
end
