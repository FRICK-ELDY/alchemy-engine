defmodule Mix.Tasks.Alchemy.Credo do
  @shortdoc "Elixir 静的解析（Credo）"
  @moduledoc """
  Credo による Elixir の静的解析を実行します。

  ## オプション

  - なし — `mix credo --strict`（厳格モード）
  - `suggest` — `mix credo`（提案のみ、strict なし）
  - `explain` — `mix credo --strict --format oneline`

  ## 使用例

      mix alchemy.credo
      mix alchemy.credo suggest
      mix alchemy.credo explain
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    mode = List.first(args)

    Mix.shell().info("")
    Mix.shell().info("========================================")
    Mix.shell().info("  AlchemyEngine — Credo")
    Mix.shell().info("  Mode: #{mode || "strict"}")
    Mix.shell().info("========================================")
    Mix.shell().info("")

    credo_args = credo_args(mode)

    case System.cmd("mix", ["credo" | credo_args], stderr_to_stdout: true) do
      {_, 0} ->
        Mix.shell().info("")
        Mix.shell().info("[PASS] credo")

      {out, _} ->
        Mix.shell().error(out)
        Mix.shell().info("")
        Mix.shell().error("[FAIL] credo")
        System.halt(1)
    end
  end

  defp credo_args("suggest"), do: []
  defp credo_args("explain"), do: ["--strict", "--format", "oneline"]
  defp credo_args(_), do: ["--strict"]
end
