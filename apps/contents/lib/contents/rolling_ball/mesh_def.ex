defmodule Content.RollingBall.MeshDef do
  @moduledoc """
  RollingBall コンテンツ用のメッシュ定義（P3-5）。

  Box3D（unit_box）、Skybox（skybox_quad）を使用。
  """
  @doc "RollingBall で使用するメッシュ定義の一覧"
  def definitions do
    Content.MeshDef.default_definitions()
  end
end
