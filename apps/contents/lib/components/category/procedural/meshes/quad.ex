defmodule Contents.Components.Category.Procedural.Meshes.Quad do
  @moduledoc """
  Quad メッシュをクライアントに渡すための定義・参照用の器。

  シェーダー用のフルスクリーン Quad 等、将来の描画で利用する骨格。
  現状は未使用のスタブ（将来利用予定）。
  """
  @doc "Quad メッシュ種別名（クライアント登録名として参照用）"
  def mesh_kind, do: :quad
end
