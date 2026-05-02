defmodule Alchemy.Input.Movement do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.input.Movement",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :dx, 1, type: :float
  field :dy, 2, type: :float
end

defmodule Alchemy.Input.Action do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.input.Action",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :name, 1, type: :string
end
