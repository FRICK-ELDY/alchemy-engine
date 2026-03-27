defmodule Network.Proto.Action do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :name, 1, type: :string
end
