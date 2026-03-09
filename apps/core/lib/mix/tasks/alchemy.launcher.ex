defmodule Mix.Tasks.Alchemy.Launcher do
  @shortdoc "ランチャー（トレイ）を起動"
  @moduledoc """
  トレイアイコンで zenohd / Phoenix Server / Client を管理するランチャーを起動します。

  ## 使用例

      mix alchemy.launcher
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    root = File.cwd!()
    manifest = Path.join(root, "native/Cargo.toml")

    Mix.shell().info("")
    Mix.shell().info("Launching launcher (tray)...")
    Mix.shell().info("")

    System.cmd("cargo", ["run", "--manifest-path", manifest, "-p", "launcher"],
      cd: root,
      into: IO.stream(:stdio, :line)
    )
  end
end
