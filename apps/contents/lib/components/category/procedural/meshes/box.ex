defmodule Contents.Components.Category.Procedural.Meshes.Box do
  @moduledoc """
  Box メッシュをクライアントに渡すための定義・参照用の器。

  DrawCommand::Box3D のパラメータ（位置・半サイズ・色）を返す。
  具体的な頂点データは Content.MeshDef 等にあり、ここでは描画コマンド用の組み立てのみ。
  """
  @doc """
  指定位置・半サイズ・色で Box3D 描画コマンド用のタプルを返す。

  戻り値は Content.MessagePackEncoder の box_3d 句で期待する形式:
  `{:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}`
  """
  @spec box_3d_command(float(), float(), float(), float(), float(), float(), {float(), float(), float(), float()}) ::
          tuple()
  def box_3d_command(x, y, z, half_w, half_h, half_d, {r, g, b, a}) do
    {:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}
  end
end
