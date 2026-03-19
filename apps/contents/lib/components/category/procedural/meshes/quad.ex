defmodule Contents.Components.Category.Procedural.Meshes.Quad do
  @moduledoc """
  スカイボックス用クリップ空間矩形（skybox_quad）のメッシュ定義。

  頂点座標はクリップ空間 (-1..1)、depth=0.999。
  色は DrawCommand::Skybox の top_color / bottom_color で上書きされる。
  頂点 4 個、インデックス 6（2 三角形）。
  """
  @doc "スカイボックス用 Quad のメッシュ定義を返す。"
  def mesh_def do
    top = {0.4, 0.6, 0.9, 1.0}
    bottom = {0.7, 0.85, 1.0, 1.0}

    vertices = [
      {{-1.0, 1.0, 0.999}, top},
      {{1.0, 1.0, 0.999}, top},
      {{1.0, -1.0, 0.999}, bottom},
      {{-1.0, -1.0, 0.999}, bottom}
    ]

    indices = [0, 1, 2, 0, 2, 3]

    %{name: :skybox_quad, vertices: vertices, indices: indices}
  end
end
