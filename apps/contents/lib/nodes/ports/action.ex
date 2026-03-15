defmodule Contents.Nodes.Ports.Action do
  @moduledoc """
  Action Port の定義（インターフェース仕様のドキュメント）。

  「いつ（When）」を司る。パルスによる実行権限の委譲。
  action in / action out で順次処理・並列処理・Sync（同期）を表現する。

  注: ノード実装は `Contents.Behaviour.Nodes`（handle_pulse/handle_sample）に従う。
  本モジュールは Port の概念と Executor/Link 層の契約を文書化するものであり、
  `@behaviour` としての実装は存在しない。
  """
end
