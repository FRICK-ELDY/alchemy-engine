defmodule Mix.Tasks.Alchemy.Router do
  @shortdoc "Zenoh Router (zenohd) を起動"
  @moduledoc """
  Zenoh Router (zenohd) をフォアグラウンドで起動します。

  前提: `cargo install eclipse-zenoh` で zenohd をインストール済みであること。
  Ctrl+C で終了します。

  待ち受けは OS で切り替える。Windows は `0.0.0.0` と `[::]`、Unix は `[::]` のみ
  （デュアルスタックで IPv4 もカバー）。TCP に加えて UDP も待つ。
  リモート Client は UDP でホストの IPv4 に接続する（TCP だとテザリングで遅延が蓄積しうる）:

      mix alchemy.client --connect udp/<HOST_IP>:7447 --room main

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
    Mix.shell().info("Remote client: mix alchemy.client --connect udp/<HOST_IP>:7447")
    Mix.shell().info("Press Ctrl+C to stop")
    Mix.shell().info("")

    System.cmd("zenohd", args, into: IO.stream(:stdio, :line))
  end

  # Windows では [::] だけだと IPv4（127.0.0.1 / LAN）に届かないため、
  # 0.0.0.0 と [::] の両方を明示する。
  # macOS/Linux では [::] へのバインドがデフォルトで IPv4（0.0.0.0）もカバーするため、
  # 両方を指定すると Address already in use になる。
  # UDP はテザリング等の TCP バッファ膨張で描画遅延が蓄積するのを避ける。
  defp listen_args do
    Enum.flat_map(listen_hosts(), fn host ->
      ["-l", "tcp/#{host}:7447", "-l", "udp/#{host}:7447"]
    end)
  end

  defp listen_hosts do
    case :os.type() do
      {:win32, _} -> ["0.0.0.0", "[::]"]
      _ -> ["[::]"]
    end
  end

  defp format_listen(args) do
    args
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      ["-l", endpoint] -> [endpoint]
      _ -> []
    end)
    |> Enum.join("  ")
  end
end
