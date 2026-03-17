defmodule Contents.Components.Category.Shader.PbsMetallic do
  @moduledoc """
  PBS Metallic シェーダーをクライアントに渡すための定義・参照用の器。

  将来的に PBR 描画で利用する骨格。現状は未使用のスタブ（将来利用予定）。
  """
  @doc "シェーダー種別名（クライアント登録名として参照用）"
  def shader_kind, do: :pbs_metallic
end
