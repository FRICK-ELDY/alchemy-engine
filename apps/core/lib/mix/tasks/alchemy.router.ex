defmodule Mix.Tasks.Alchemy.Router do
  @shortdoc "Zenoh Router (zenohd) を起動"
  @moduledoc """
  Zenoh Router (zenohd) をフォアグラウンドで起動します。

  前提: `cargo install eclipse-zenoh` で zenohd をインストール済みであること。
  Ctrl+C で終了します。

  IPv4 は `0.0.0.0:7447`（localhost と LAN / テザリングの両方）、IPv6 は `[::]:7447`。
  リモート Client はホストの IPv4 に接続する:

      mix alchemy.client --connect tcp/<HOST_IP>:7447 --room main

  ## 使用例

      mix alchemy.router
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("")
    Mix.shell().info("Starting Zenoh Router (zenohd)...")
    Mix.shell().info("listen: tcp/0.0.0.0:7447  tcp/[::]:7447")
    Mix.shell().info("Remote client: mix alchemy.client --connect tcp/<HOST_IP>:7447")
    Mix.shell().info("Press Ctrl+C to stop")
    Mix.shell().info("")

    # Windows では tcp/[::]:7447 だけだと IPv4（127.0.0.1 / LAN）に届かない。
    # 0.0.0.0 で localhost とテザリング / LAN の IPv4 を同時に待つ。
    args = ["-l", "tcp/0.0.0.0:7447", "-l", "tcp/[::]:7447"]
    System.cmd("zenohd", args, into: IO.stream(:stdio, :line))
  end
end
