defmodule Contents.SceneBehaviour do
  @moduledoc """
  シーンコールバックの動作定義。

  `Contents.Behaviour.Scenes` を拡張した後方互換用の契約。
  各シーンは init/1, update/2, render_type/0 を実装する。
  Contents.Scenes.Stack がスタックで管理し、Contents.Events.Game が update を呼び出す。

  新規・将来コンテンツでは、Scene が空間の原点（origin）を持ち、着地点は Object への参照
  （例: `landing_object`）で持つことを推奨。root_object 必須は廃止予定。詳細は
  `Contents.Behaviour.Scenes` および docs/plan/current/scene-origin-and-landing-reference-plan.md を参照。
  """
  use Contents.Behaviour.Scenes
end
