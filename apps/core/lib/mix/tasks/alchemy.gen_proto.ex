defmodule Mix.Tasks.Alchemy.GenProto do
  @shortdoc "proto/*.proto から Elixir / Rust の生成コードを作る（単一エントリ）"
  @moduledoc """
  `protoc` / `prost-build` による生成処理を **この Mix タスクに集約**する。

  OS ごとのシェルスクリプト（`scripts/*.sh` 等）は置かず、クロスプラットフォームで同じ手順にする。

  ## 実装状況

  生成ロジックは段階的に本モジュールへ追加する。詳細・契約・CI 要件は
  `workspace/2_todo/protobuf-full-automation-procedure.md` を参照。

  ## 使用例（予定）

      mix alchemy.gen_proto
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("")
    Mix.shell().info(
      "[alchemy.gen_proto] Protobuf 生成の公式エントリ（現在は案内のみ / NO-OP。実装は手順書に沿って本タスクへ集約予定）。"
    )
    Mix.shell().info("手順書: workspace/2_todo/protobuf-full-automation-procedure.md")
    Mix.shell().info("")
  end
end
