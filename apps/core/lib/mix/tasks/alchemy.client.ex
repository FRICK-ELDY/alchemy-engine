defmodule Mix.Tasks.Alchemy.Client do
  @shortdoc "VRAlchemy クライアントを起動"
  @moduledoc """
  VRAlchemy（デスクトップクライアント）を起動します。

  前提: zenohd と Phoenix Server (mix run --no-halt) を別ターミナルで起動済みであること。

  ## オプション

  - `--connect URL` — Zenoh 接続先（デフォルト: tcp/127.0.0.1:7447）
  - `--room ID` — ルーム ID（デフォルト: main）

  ## 使用例

      mix alchemy.client
      mix alchemy.client --connect tcp/127.0.0.1:7447 --room main
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [connect: :string, room: :string],
        aliases: [c: :connect, r: :room]
      )

    connect = Keyword.get(opts, :connect, "tcp/127.0.0.1:7447")
    room = Keyword.get(opts, :room, "main")

    root = File.cwd!()
    manifest = Path.join(root, "native/Cargo.toml")

    Mix.shell().info("")
    Mix.shell().info("Alchemy Client - connect=#{connect} room=#{room}")
    Mix.shell().info("(Ensure zenohd and mix run are running first)")
    Mix.shell().info("")

    System.cmd(
      "cargo",
      [
        "run",
        "--manifest-path",
        manifest,
        "-p",
        "app",
        "--",
        "--connect",
        connect,
        "--room",
        room
      ],
      cd: root,
      into: IO.stream(:stdio, :line)
    )
  end
end
