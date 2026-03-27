defmodule Network.Proto.Movement do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :dx, 1, type: :float
  field :dy, 2, type: :float
end
