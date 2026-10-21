defmodule Mix.Tasks.Alchemy.Build do
  @shortdoc "（移管済み）クライアントは alchemy-client をビルド"
  @moduledoc """
  VRAlchemy クライアントは [alchemy-client](https://github.com/FRICK-ELDY/alchemy-client) へ移管しました。

  本リポの Rust ワークスペースは **`nif` のみ**です。

      cd ../alchemy-client   # または親スーパープロジェクトの client/
      cargo build -p app
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.raise("""
    VRAlchemy クライアントは alchemy-client へ移管しました。

      cd ../alchemy-client && cargo build -p app

    親スーパープロジェクトでは `bin\\client.bat` / `client/` submodule を使ってください。
    """)
  end
end
