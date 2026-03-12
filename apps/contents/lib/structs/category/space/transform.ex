defmodule Structs.Category.Space.Transform do
  @moduledoc """
  変換型。位置・回転・スケールを表す。

  ## 構造

      %{
        position: Value.Float.t3(),    # 位置 (x, y, z)
        rotation: Value.Float.quaternion(),  # 回転 (x, y, z, w)
        scale: Value.Float.t3()        # スケール (x, y, z)
      }
  """
  alias Structs.Category.Value.Float, as: ValueFloat

  @type t :: %{
          required(:position) => ValueFloat.t3(),
          required(:rotation) => ValueFloat.quaternion(),
          required(:scale) => ValueFloat.t3()
        }

  @doc """
  デフォルトの Transform を生成する。

  位置・回転はゼロ/単位、スケールは (1, 1, 1)。
  """
  @spec new() :: t()
  def new do
    %{
      position: {0.0, 0.0, 0.0},
      rotation: {0.0, 0.0, 0.0, 1.0},
      scale: {1.0, 1.0, 1.0}
    }
  end
end
