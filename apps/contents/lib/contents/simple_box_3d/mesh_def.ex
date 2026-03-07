defmodule Content.SimpleBox3D.MeshDef do
  @moduledoc """
  SimpleBox3D コンテンツ用のメッシュ定義（P3-5）。

  Box3D（unit_box）、Skybox（skybox_quad）、GridPlane（grid_plane）を使用。
  """
  @doc "SimpleBox3D で使用するメッシュ定義の一覧"
  def definitions do
    Content.MeshDef.default_definitions()
  end
end
