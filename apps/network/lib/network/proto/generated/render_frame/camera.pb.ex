defmodule Alchemy.Render.CameraParams do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.CameraParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :kind, 0

  field :camera_2d, 1, type: Alchemy.Render.Camera2d, json_name: "camera2d", oneof: 0
  field :camera_3d, 2, type: Alchemy.Render.Camera3d, json_name: "camera3d", oneof: 0
end

defmodule Alchemy.Render.Camera2d do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.Camera2d",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :offset_x, 1, type: :float, json_name: "offsetX"
  field :offset_y, 2, type: :float, json_name: "offsetY"
end

defmodule Alchemy.Render.Camera3d do
  @moduledoc false

  use Protobuf,
    full_name: "alchemy.render.Camera3d",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :eye, 1, repeated: true, type: :float
  field :target, 2, repeated: true, type: :float
  field :up, 3, repeated: true, type: :float
  field :fov_deg, 4, type: :float, json_name: "fovDeg"
  field :near, 5, type: :float
  field :far, 6, type: :float
end
