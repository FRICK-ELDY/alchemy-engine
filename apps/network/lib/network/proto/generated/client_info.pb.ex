defmodule Alchemy.Client.ClientInfo do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.client.ClientInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field(:os, 1, type: :string)
  field(:arch, 2, type: :string)
  field(:family, 3, type: :string)
end
