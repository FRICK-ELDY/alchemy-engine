defmodule Mix.Tasks.Alchemy.Router do
  @shortdoc "Zenoh Router (zenohd) を起動"
  @moduledoc """
  Zenoh Router (zenohd) をフォアグラウンドで起動します。

  前提: `cargo install eclipse-zenoh` で zenohd をインストール済みであること。
  Ctrl+C で終了します。

  ## 使用例

      mix alchemy.router
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("")
    Mix.shell().info("Starting Zenoh Router (zenohd)...")
    Mix.shell().info("Press Ctrl+C to stop")
    Mix.shell().info("")

    System.cmd("zenohd", [], into: IO.stream(:stdio, :line))
  end
end
