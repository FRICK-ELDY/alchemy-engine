defmodule Contents.SceneBehaviour do
  @moduledoc """
  シーンコールバックの動作定義。

  `Contents.Behaviour.Scenes` を拡張した後方互換用の契約。
  各シーンは init/1, update/2, render_type/0 を実装する。
  Contents.Scenes.Stack がスタックで管理し、Contents.Events.Game が update を呼び出す。

  方針: 空間の原点（origin）は Scene が持ち、着地点は Object への参照（例: `landing_object`）のみとする。
  root_object 必須は廃止。既存コンテンツは移行対象外。実施計画: workspace/7_done/scene-origin-and-landing-reference-plan.md
  """
  use Contents.Behaviour.Scenes
end
