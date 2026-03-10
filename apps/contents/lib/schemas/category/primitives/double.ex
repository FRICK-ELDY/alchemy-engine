defmodule Schemas.Category.Primitives.Double do
  @moduledoc """
  64 ビット浮動小数型（倍精度）。スカラー、2〜4 要素ベクトル、2x2〜4x4 行列、クォータニオン。

  Elixir の `float()` と同様に 64 ビット精度です。
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
