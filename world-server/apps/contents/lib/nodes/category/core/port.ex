defmodule Contents.Nodes.Category.Core.Port do
  @moduledoc """
  ノードの Port（入出力端子）を表す概念。

  action in/out, logic in/out の種類と型情報を持つ想定。
  logic の値型には `Structs.Category.Value.*`, `Structs.Category.Text.String.t/0` 等の利用を想定。
  `defstruct` や `@type` は未定義（プレースホルダー）。設計確定後に定義予定。
  """
end
