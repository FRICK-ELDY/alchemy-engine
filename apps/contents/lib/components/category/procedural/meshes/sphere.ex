defmodule Contents.Components.Category.Procedural.Meshes.Sphere do
  @moduledoc """
  単位球（unit_sphere）メッシュの定義と DrawCommand 用ヘルパー。

  - `mesh_def/0`: 半径 0.5・中心原点の球メッシュ定義（緯度経度分割）を返す。
  - `sphere_3d_command/5`: DrawCommand::Sphere3D 用のタプルを返す。
  """
  @stack_segments 6
  @slice_segments 10

  @doc """
  単位球（中心原点、半径 0.5）。

  色は DrawCommand で上書きされるためここでは白。
  """
  def mesh_def do
    radius = 0.5
    white = {1.0, 1.0, 1.0, 1.0}
    stacks = @stack_segments
    slices = @slice_segments

    vertices =
      for i <- 0..stacks,
          j <- 0..(slices - 1) do
        t = i / stacks
        phi = -:math.pi() / 2 + :math.pi() * t
        theta = 2 * :math.pi() * j / slices
        c_phi = :math.cos(phi)
        x = radius * c_phi * :math.cos(theta)
        z = radius * c_phi * :math.sin(theta)
        y = radius * :math.sin(phi)
        {{x, y, z}, white}
      end

    indices =
      for i <- 0..(stacks - 1), j <- 0..(slices - 1) do
        jn = rem(j + 1, slices)
        a = i * slices + j
        b = (i + 1) * slices + j
        c = (i + 1) * slices + jn
        d = i * slices + jn
        [a, b, c, a, c, d]
      end
      |> List.flatten()

    %{name: :unit_sphere, vertices: vertices, indices: indices}
  end

  @doc """
  中心 `(x, y, z)`・半径 `radius`・色 `rgba` で Sphere3D 描画コマンド用のタプルを返す。

  戻り値は `Content.FrameEncoder` の sphere_3d 句で期待する形式:
  `{:sphere_3d, x, y, z, radius, {r, g, b, a}}`
  """
  def sphere_3d_command(x, y, z, radius, {r, g, b, a}) do
    {:sphere_3d, x, y, z, radius, {r, g, b, a}}
  end
end
