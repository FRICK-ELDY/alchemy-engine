defmodule Contents.Components.Category.Procedural.Meshes.Box do
  @moduledoc """
  単位ボックス（unit_box）メッシュの定義と DrawCommand 用ヘルパー。

  - `mesh_def/0`: 辺長 1・中心原点のボックスメッシュ定義（頂点・インデックス）を返す。
  - `box_3d_command/7`: DrawCommand::Box3D 用のタプルを返す。
  """
  @doc """
  単位ボックス（中心原点、辺長 1）のメッシュ定義。

  頂点 8 個、インデックス 36（12 三角形）。
  色は DrawCommand で上書きされるためここでは白。
  """
  def mesh_def do
    x0 = -0.5
    x1 = 0.5
    y0 = -0.5
    y1 = 0.5
    z0 = -0.5
    z1 = 0.5
    white = {1.0, 1.0, 1.0, 1.0}

    vertices = [
      {{x0, y0, z0}, white},
      {{x1, y0, z0}, white},
      {{x1, y1, z0}, white},
      {{x0, y1, z0}, white},
      {{x0, y0, z1}, white},
      {{x1, y0, z1}, white},
      {{x1, y1, z1}, white},
      {{x0, y1, z1}, white}
    ]

    indices = [
      0,
      1,
      2,
      0,
      2,
      3,
      5,
      4,
      7,
      5,
      7,
      6,
      4,
      0,
      3,
      4,
      3,
      7,
      1,
      5,
      6,
      1,
      6,
      2,
      3,
      2,
      6,
      3,
      6,
      7,
      4,
      5,
      1,
      4,
      1,
      0
    ]

    %{name: :unit_box, vertices: vertices, indices: indices}
  end

  @doc """
  指定位置・半サイズ・色で Box3D 描画コマンド用のタプルを返す。

  戻り値は Content.FrameEncoder の box_3d 句で期待する形式:
  `{:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}`
  """
  def box_3d_command(x, y, z, half_w, half_h, half_d, {r, g, b, a}) do
    {:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}
  end
end
