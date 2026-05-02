defmodule Alchemy.Render.MeshVertex do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.MeshVertex",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :position, 1, repeated: true, type: :float
  field :color, 2, repeated: true, type: :float
end

defmodule Alchemy.Render.MeshDef do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.MeshDef",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :vertices, 2, repeated: true, type: Alchemy.Render.MeshVertex
  field :indices, 3, repeated: true, type: :uint32
end
