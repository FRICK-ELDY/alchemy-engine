defmodule GameEngine.MapLoader do
  @moduledoc """
  マップ ID に応じた障害物リストを提供する。
  各要素は `{x, y, radius, kind}` のタプル。
  kind: 0=木, 1=岩
  """

  def obstacles_for_map(:plain), do: []

  def obstacles_for_map(:forest) do
    [
      {512.0, 512.0, 40.0, 0},
      {1024.0, 768.0, 30.0, 1},
      {1536.0, 256.0, 40.0, 0},
      {768.0, 1024.0, 35.0, 1},
      {2048.0, 2048.0, 50.0, 0},
      {2560.0, 1280.0, 30.0, 1},
      {1280.0, 2560.0, 40.0, 0},
      {640.0, 640.0, 25.0, 1},
    ]
  end

  def obstacles_for_map(:minimal) do
    [
      {512.0, 360.0, 40.0, 0},
      {768.0, 400.0, 30.0, 1},
    ]
  end

  def obstacles_for_map(_unknown), do: []
end
