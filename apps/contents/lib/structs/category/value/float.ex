defmodule Structs.Category.Value.Float do
  @moduledoc """
  浮動小数型。スカラー、2〜4 要素ベクトル、2x2〜4x4 行列、クォータニオン。

  Elixir の `float()` は 64 ビット（倍精度）。言語レベルで高い精度を維持し、
  Resonite 等の 32 ビット空間との境界で cast する想定。
  """
  @type t :: float()
  @type t2 :: {t(), t()}
  @type t3 :: {t(), t(), t()}
  @type t4 :: {t(), t(), t(), t()}
  @type t2x2 :: {{t(), t()}, {t(), t()}}
  @type t3x3 :: {{t(), t(), t()}, {t(), t(), t()}, {t(), t(), t()}}
  @type t4x4 ::
          {{t(), t(), t(), t()}, {t(), t(), t(), t()}, {t(), t(), t(), t()}, {t(), t(), t(), t()}}
  @type quaternion :: {t(), t(), t(), t()}
end
