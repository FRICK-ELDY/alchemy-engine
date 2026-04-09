defmodule Content.FrameEncoder.Proto do
  @moduledoc false

  # DrawCommand / Camera / Ui / MeshDef / injection エンコード用の共有ヘルパー。

  def pb_float(n), do: n * 1.0

  def color_tuple_to_pb_list({r, g, b, a}) do
    [pb_float(r), pb_float(g), pb_float(b), pb_float(a)]
  end

  def vec2_to_pb_list({a, b}), do: [pb_float(a), pb_float(b)]

  def vec3_to_pb_list({a, b, c}), do: [pb_float(a), pb_float(b), pb_float(c)]
end
