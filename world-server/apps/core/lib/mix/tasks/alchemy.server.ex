defmodule Mix.Tasks.Alchemy.Server do
  @shortdoc "Phoenix Server を起動"
  @moduledoc """
  Phoenix Server (mix run --no-halt) を起動します。

  ポート 4000 で待ち受けます。Ctrl+C で終了します。

  ## 使用例

      mix alchemy.server
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("")
    Mix.shell().info("Starting Phoenix Server...")
    Mix.shell().info("Press Ctrl+C to stop")
    Mix.shell().info("")

    Mix.Task.run("run", ["--no-halt"])
  end
end
