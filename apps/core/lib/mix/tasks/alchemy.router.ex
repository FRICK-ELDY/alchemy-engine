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

    # Windows では tcp/[::]:7447 だけだと 127.0.0.1 に届かない場合があるため、
    # tcp/127.0.0.1:7447 を明示して localhost 接続を確実にする。
    # tcp/[::]:7447 も指定して LAN 等からの接続を維持する。
    args = ["-l", "tcp/127.0.0.1:7447", "-l", "tcp/[::]:7447"]
    System.cmd("zenohd", args, into: IO.stream(:stdio, :line))
  end
end
