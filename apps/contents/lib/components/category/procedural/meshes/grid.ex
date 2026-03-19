defmodule Contents.Components.Category.Procedural.Meshes.Grid do
  @moduledoc """
  XZ 平面グリッド（GridPlane）のメッシュ定義。

  パラメータに応じて頂点を生成する。インデックスは空（LineList）。
  Rust 側が LineList として描画する。

  ## オプション
  - `:size` — 一辺のサイズ（デフォルト 20.0）
  - `:divisions` — 分割数（デフォルト 20）
  - `:color` — RGBA タプル（デフォルト {0.3, 0.3, 0.3, 1.0}）
  """
  @doc "XZ 平面グリッドのメッシュ定義を返す。vertices を grid_plane_verts コマンドに渡す。"
  def grid_plane(opts \\ []) do
    size = Keyword.get(opts, :size, 20.0)
    divisions = Keyword.get(opts, :divisions, 20)
    color = Keyword.get(opts, :color, {0.3, 0.3, 0.3, 1.0})

    half = size / 2.0
    step = size / divisions
    n = divisions + 1

    vertices =
      for i <- 0..(n - 1) do
        t = -half + i * step

        [
          {{-half, 0.0, t}, color},
          {{half, 0.0, t}, color},
          {{t, 0.0, -half}, color},
          {{t, 0.0, half}, color}
        ]
      end
      |> List.flatten()

    %{name: :grid_plane, vertices: vertices, indices: []}
  end
end
