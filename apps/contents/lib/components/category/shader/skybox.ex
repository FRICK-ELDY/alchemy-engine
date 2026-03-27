defmodule Contents.Components.Category.Shader.Skybox do
  @moduledoc """
  Skybox シェーダーをクライアントに渡すための定義・参照用の器。

  DrawCommand::Skybox のパラメータ（上色・下色）を返す。
  """
  @doc """
  指定の上色・下色で Skybox 描画コマンド用のタプルを返す。

  戻り値は Content.FrameEncoder の skybox 句で期待する形式:
  `{:skybox, {tr, tg, tb, ta}, {br, bg, bb, ba}}`
  """
  @spec skybox_command({float(), float(), float(), float()}, {float(), float(), float(), float()}) ::
          tuple()
  def skybox_command(top_color, bottom_color) do
    {:skybox, top_color, bottom_color}
  end
end
