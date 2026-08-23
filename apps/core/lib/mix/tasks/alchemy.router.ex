defmodule Mix.Tasks.Alchemy.Router do
  @shortdoc "Zenoh Router (zenohd) を起動"
  @moduledoc """
  Zenoh Router (zenohd) をフォアグラウンドで起動します。

  前提: `cargo install eclipse-zenoh` で zenohd をインストール済みであること。
  Ctrl+C で終了します。

  待ち受けは OS で切り替える。Windows は `tcp/0.0.0.0:7447` と `tcp/[::]:7447`、
  Unix（macOS / Linux）は `tcp/[::]:7447` のみ（デュアルスタックで IPv4 もカバー）。
  リモート Client はホストの IPv4 に接続する:

      mix alchemy.client --connect tcp/<HOST_IP>:7447 --room main

  ## 使用例

      mix alchemy.router
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    args = listen_args()

    Mix.shell().info("")
    Mix.shell().info("Starting Zenoh Router (zenohd)...")
    Mix.shell().info("listen: #{format_listen(args)}")
    Mix.shell().info("Remote client: mix alchemy.client --connect tcp/<HOST_IP>:7447")
    Mix.shell().info("Press Ctrl+C to stop")
    Mix.shell().info("")

    System.cmd("zenohd", args, into: IO.stream(:stdio, :line))
  end

  # Windows では tcp/[::]:7447 だけだと IPv4（127.0.0.1 / LAN）に届かないため、
  # 0.0.0.0 と [::] の両方を明示する。
  # macOS/Linux では [::] へのバインドがデフォルトで IPv4（0.0.0.0）もカバーするため、
  # 両方を指定すると Address already in use になる。
  defp listen_args do
    case :os.type() do
      {:win32, _} -> ["-l", "tcp/0.0.0.0:7447", "-l", "tcp/[::]:7447"]
      _ -> ["-l", "tcp/[::]:7447"]
    end
  end

  defp format_listen(args) do
    args
    |> Enum.chunk_every(2)
    |> Enum.map(fn ["-l", endpoint] -> endpoint end)
    |> Enum.join("  ")
  end
end
