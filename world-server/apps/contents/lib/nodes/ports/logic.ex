defmodule Contents.Nodes.Ports.Logic do
  @moduledoc """
  Logic Port の定義（インターフェース仕様のドキュメント）。

  「何を（What）」を司る。情報の参照と変換。
  logic in / logic out でストリームまたは Value の受け渡しを表現する。

  注: ノード実装は `Contents.Behaviour.Nodes`（handle_pulse/handle_sample）に従う。
  本モジュールは Port の概念と Executor/Link 層の契約を文書化するものであり、
  `@behaviour` としての実装は存在しない。
  """
end
