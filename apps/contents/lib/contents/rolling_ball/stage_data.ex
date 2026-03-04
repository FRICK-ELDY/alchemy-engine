defmodule Content.RollingBall.StageData do
  @moduledoc """
  ローリングボール迷路のステージ定義データ。

  ## 座標系
  グリッド座標 (col, row) → ワールド座標 (x, z) の変換:
    x = (col - floor_size / 2 + 0.5) * tile_size
    z = (row - floor_size / 2 + 0.5) * tile_size

  タイルサイズは 2.0。フロアサイズ 8×8 → ワールド幅 16.0。
  """

  # タイルを大きくして枚数を減らす（8×8 = 64枚、10×10 = 100枚）
  @tile_size 2.0
  @max_retries 3

  @doc "ステージ番号（1〜3）からステージデータを返す"
  def get(1) do
    floor_size = 8

    %{
      stage: 1,
      floor_size: floor_size,
      tile_size: @tile_size,
      max_retries: @max_retries,
      # 左下スタート → 右上ゴール
      ball_start: {-6.0, -6.0},
      goal_pos: {6.0, 6.0},
      # 穴：中央付近に4つ（通路を残す）
      holes: [
        {2, 2},
        {5, 2},
        {2, 5},
        {5, 5}
      ],
      # 障害物：中央に1つ（ゴールへの直線ルートを塞ぐ）
      obstacles: [
        {0.0, 0.0}
      ],
      moving_obstacles: []
    }
  end

  def get(2) do
    floor_size = 10

    %{
      stage: 2,
      floor_size: floor_size,
      tile_size: @tile_size,
      max_retries: @max_retries,
      ball_start: {-8.0, -8.0},
      goal_pos: {8.0, 8.0},
      holes: [
        {1, 1},
        {4, 1},
        {8, 1},
        {1, 4},
        {8, 4},
        {1, 8},
        {4, 8},
        {8, 8}
      ],
      obstacles: [
        {2.0, 0.0},
        {-2.0, 0.0},
        {0.0, 2.0},
        {0.0, -2.0}
      ],
      moving_obstacles: []
    }
  end

  def get(3) do
    floor_size = 10

    %{
      stage: 3,
      floor_size: floor_size,
      tile_size: @tile_size,
      max_retries: @max_retries,
      ball_start: {-8.0, -8.0},
      goal_pos: {8.0, 8.0},
      holes: [
        {1, 1},
        {5, 1},
        {8, 1},
        {1, 5},
        {8, 5},
        {1, 8},
        {5, 8},
        {8, 8},
        {3, 3},
        {6, 3},
        {3, 6},
        {6, 6},
        {4, 0},
        {0, 4},
        {9, 4},
        {4, 9}
      ],
      obstacles: [
        {4.0, 0.0},
        {-4.0, 0.0},
        {0.0, 4.0},
        {0.0, -4.0}
      ],
      moving_obstacles: [
        %{id: 0, x: 2.0, z: 2.0, vx: 3.0, vz: 0.0, range: 4.0},
        %{id: 1, x: -2.0, z: -2.0, vx: 0.0, vz: 3.0, range: 4.0},
        %{id: 2, x: 2.0, z: -2.0, vx: -3.0, vz: 0.0, range: 4.0},
        %{id: 3, x: -2.0, z: 2.0, vx: 0.0, vz: -3.0, range: 4.0}
      ]
    }
  end

  @doc "ステージ数の上限"
  def max_stage, do: 3

  @doc "グリッド座標 {col, row} をワールド座標 {x, z} に変換する"
  def grid_to_world(col, row, floor_size, tile_size \\ @tile_size) do
    x = (col - floor_size / 2 + 0.5) * tile_size
    z = (row - floor_size / 2 + 0.5) * tile_size
    {x, z}
  end

  @doc "フロアの全タイル座標リスト（穴を除く）を返す"
  def floor_tiles(stage_data) do
    %{floor_size: n, holes: holes, tile_size: ts} = stage_data
    hole_set = MapSet.new(holes)

    for col <- 0..(n - 1), row <- 0..(n - 1), not MapSet.member?(hole_set, {col, row}) do
      {x, z} = grid_to_world(col, row, n, ts)
      {x, z}
    end
  end

  @doc "穴のワールド座標リストを返す（落下判定用）"
  def hole_positions(stage_data) do
    %{floor_size: n, holes: holes, tile_size: ts} = stage_data

    Enum.map(holes, fn {col, row} ->
      grid_to_world(col, row, n, ts)
    end)
  end
end
