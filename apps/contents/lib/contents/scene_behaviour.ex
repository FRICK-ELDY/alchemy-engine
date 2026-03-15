defmodule Contents.SceneBehaviour do
  @moduledoc """
  シーンコールバックの動作定義。

  `Contents.Scenes.Core.Behaviour` を拡張した後方互換用の契約。
  各シーンは init/1, update/2, render_type/0 を実装する。
  SceneStack がスタックで管理し、GameEvents が update を呼び出す。

  新規・将来コンテンツでは state に `root_object`（ユーザーが Scene に降り立つ着地点）を
  含めることを推奨。詳細は `Contents.Scenes.Core.Behaviour` を参照。
  """
  use Contents.Scenes.Core.Behaviour
end
