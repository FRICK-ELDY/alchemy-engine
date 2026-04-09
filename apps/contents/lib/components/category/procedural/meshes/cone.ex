defmodule Contents.Components.Category.Procedural.Meshes.Cone do
  @moduledoc """
  単位円錐（unit_cone）メッシュの定義と DrawCommand 用ヘルパー。

  - `mesh_def/0`: 正立円錐（底 y=-0.5、先端 y=+0.5、底面半径 0.5）。`unit_box` と同じ軸平行バウンディング。
  - `cone_3d_command/7`: DrawCommand::Cone3D 用のタプルを返す。
  """
  @slice_segments 12

  @doc """
  単位円錐（頂点は `unit_box` と同様に y ∈ [-0.5, 0.5] の軸平行バウンディング内。厳密な幾何中心＝円錐の重心ではない）。

  色は DrawCommand で上書きされる。
  """
  def mesh_def do
    n = @slice_segments
    white = {1.0, 1.0, 1.0, 1.0}
    apex = {{0.0, 0.5, 0.0}, white}

    ring =
      for j <- 0..(n - 1) do
        theta = 2 * :math.pi() * j / n
        x = 0.5 * :math.cos(theta)
        z = 0.5 * :math.sin(theta)
        {{x, -0.5, z}, white}
      end

    base_center = {{0.0, -0.5, 0.0}, white}
    vertices = [apex] ++ ring ++ [base_center]

    side_tris =
      for j <- 0..(n - 1) do
        jn = rem(j + 1, n)
        [0, 1 + j, 1 + jn]
      end
      |> List.flatten()

    base_idx = n + 1

    base_tris =
      for j <- 0..(n - 1) do
        jn = rem(j + 1, n)
        [base_idx, 1 + jn, 1 + j]
      end
      |> List.flatten()

    indices = side_tris ++ base_tris
    %{name: :unit_cone, vertices: vertices, indices: indices}
  end

  @doc """
  指定位置・半サイズ・色で Cone3D 描画コマンド用のタプルを返す。

  戻り値は `Content.FrameEncoder` の `cone_3d` 句で期待する形式:
  `{:cone_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}`
  """
  def cone_3d_command(x, y, z, half_w, half_h, half_d, {r, g, b, a}) do
    {:cone_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}
  end
end
