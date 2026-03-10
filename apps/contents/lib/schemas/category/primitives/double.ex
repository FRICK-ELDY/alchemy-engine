defmodule Schemas.Category.Primitives.Double do
  @moduledoc """
  64 ビット浮動小数型。スカラー、2〜4 要素ベクトル、2x2〜4x4 行列、クォータニオン。
  """
  @type t :: float()
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
  @type t2x2 :: {{t(), t()}, {t(), t()}}
  @type t3x3 :: {{t(), t(), t()}, {t(), t(), t()}, {t(), t(), t()}}
  @type t4x4 :: {{t(), t(), t(), t()}, {t(), t(), t(), t()}, {t(), t(), t(), t()}, {t(), t(), t(), t()}}
  @type quaternion :: {t(), t(), t(), t()}
end
