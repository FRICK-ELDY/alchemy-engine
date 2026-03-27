defmodule Network.Proto.ClientInfo do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :os, 1, type: :string
  field :arch, 2, type: :string
  field :family, 3, type: :string
end
