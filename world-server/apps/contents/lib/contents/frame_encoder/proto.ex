defmodule Contents.FrameEncoder.Proto do
  @moduledoc false

  # DrawCommand / Camera / Ui / MeshDef / injection エンコード用の共有ヘルパー。

  # 空間量（座標・ワールド寸法）。ワイヤは proto3 `double`（binary64）。
  def pb_double(n) when is_number(n), do: n * 1.0

  # 色・UV・ピクセル量。戻り値を binary32 に量子化する。
  # ワイヤ型は生成フィールドが決める。ここでの量子化は、ヘルパーの取り違えを Elixir 上で見えるようにする。
  def pb_float(n) when is_number(n) do
    <<rounded::float-32>> = <<n * 1.0::float-32>>
    rounded
  end

  def color_tuple_to_pb_list({r, g, b, a}) do
    [pb_float(r), pb_float(g), pb_float(b), pb_float(a)]
  end

  def vec2_to_pb_list({a, b}), do: [pb_float(a), pb_float(b)]

  def vec3_to_pb_list({a, b, c}), do: [pb_double(a), pb_double(b), pb_double(c)]
end
