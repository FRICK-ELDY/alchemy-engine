defmodule Content.MeshDef do
  @moduledoc """
  3D メッシュ定義の Elixir 側形式（P3-2）。

  ## 設計方針

  - **定義**: Elixir が持つ（本モジュール + コンテンツ別 mesh_def.ex）
  - **実行**: Rust が受け取り create_buffer で登録し描画

  ## 形式

  ```elixir
  %{
    name: :unit_box,              # 登録名（Atom または binary）
    vertices: [                   # 頂点リスト
      {{x, y, z}, {r, g, b, a}},  # position, color
      ...
    ],
    indices: [0, 1, 2, ...]       # インデックス（LineList の場合は空リスト）
  }
  ```

  ## 属性

  - position: {x, y, z} — ワールド座標（単位メッシュの場合は相対座標）
  - color: {r, g, b, a} — RGBA（0.0〜1.0）

  トポロジ:
  - indices が非空 → TriangleList
  - indices が空 → LineList（頂点をそのままラインとして使用）
  """

  @type vertex :: {{float(), float(), float()}, {float(), float(), float(), float()}}
  @type mesh_def :: %{
          required(:name) => atom() | binary(),
          required(:vertices) => [vertex()],
          required(:indices) => [non_neg_integer()]
        }

  @doc """
  単位ボックス（中心原点、辺長 1）のメッシュ定義。

  DrawCommand::Box3D のインスタンスパラメータ（x, y, z, half_w, half_h, half_d, color）
  でスケール・移動・色が適用される。

  頂点: 8 個（AABB の 8 隅）
  インデックス: 36（12 三角形）
  """
  @spec unit_box() :: mesh_def()
  def unit_box do
    # 辺長 1、中心原点 → -0.5 .. 0.5
    x0 = -0.5
    x1 = 0.5
    y0 = -0.5
    y1 = 0.5
    z0 = -0.5
    z1 = 0.5

    # 色は DrawCommand で上書きされるため、ここでは白 (1,1,1,1)
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

    # -Z面, +Z面, -X面, +X面, +Y面, -Y面
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
  スカイボックス用クリップ空間矩形のメッシュ定義。

  頂点座標はクリップ空間 (-1..1)、depth=0.999。
  色は DrawCommand::Skybox の top_color / bottom_color で上書きされる。
  ここでは仮の色（上空青・地平白）。

  頂点: 4 個
  インデックス: 6（2 三角形）
  """
  @spec skybox_quad() :: mesh_def()
  def skybox_quad do
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

  @doc """
  XZ 平面グリッドの頂点を生成する（GridPlane 用）。

  パラメータに応じて毎フレーム頂点を生成する。
  インデックスは空（LineList）。

  ## オプション

  - `:size` - 一辺のサイズ（デフォルト 20.0）
  - `:divisions` - 分割数（デフォルト 20）
  - `:color` - RGBA タプル（デフォルト {0.3, 0.3, 0.3, 1.0}）

  ## 戻り値

  vertices のリスト。indices は空の mesh_def 形式で返す。
  （Rust 側が LineList として描画するため）
  """
  @spec grid_plane(keyword()) :: mesh_def()
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

  @doc """
  3D コンテンツで共通利用するメッシュ定義の一覧。

  コンテンツ側は `mesh_definitions/0` をオーバーライドして
  追加のメッシュを定義できる。
  """
  @spec default_definitions() :: [mesh_def()]
  def default_definitions do
    [unit_box(), skybox_quad()]
  end
end
