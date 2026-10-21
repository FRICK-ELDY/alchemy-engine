defmodule Structs.Category.Value.Color do
  @moduledoc """
  色型。拡張（RGBA 等）および 32 ビット詰め表現。

  - `t/0`: バイト表現（各成分 0..255）
  - `normalized_t/0`: 正規化表現（各成分 0.0..1.0 の float）。描画 API 等で利用。
  """
  @type t :: {0..255, 0..255, 0..255, 0..255}
  @type normalized_t :: {float(), float(), float(), float()}
  @type t32 :: non_neg_integer()

  @doc """
  バイト表現を正規化表現に変換する。

  前提: 入力は `t/0`（各成分 0..255）を想定する。0..255 外を渡すと 0.0..1.0 外の正規化値になる。
  """
  @spec to_normalized(t()) :: normalized_t()
  def to_normalized({r, g, b, a}) do
    {r / 255, g / 255, b / 255, a / 255}
  end

  @doc """
  正規化表現をバイト表現に変換する。丸めは四捨五入。

  前提: 入力は各成分 0.0..1.0 の 4-tuple を想定する。範囲外は `clamp_byte` により 0 または 255 に丸まる。
  """
  @spec from_normalized(normalized_t()) :: t()
  def from_normalized({r, g, b, a}) do
    {
      round(r * 255) |> clamp_byte(),
      round(g * 255) |> clamp_byte(),
      round(b * 255) |> clamp_byte(),
      round(a * 255) |> clamp_byte()
    }
  end

  defp clamp_byte(n) when n < 0, do: 0
  defp clamp_byte(n) when n > 255, do: 255
  defp clamp_byte(n), do: n
end
