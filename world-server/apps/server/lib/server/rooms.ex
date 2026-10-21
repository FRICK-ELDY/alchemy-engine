defmodule Server.Rooms do
  @moduledoc """
  `Core.RoomSupervisor` と `:main` の起動を `rest_for_one` で束ねる。

  `RoomSupervisor` が intensity 超過で再起動すると、後続の `Server.MainRoom` も
  再起動し、空になったスーパーバイザへ `:main` を作り直す。
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Core.RoomSupervisor,
      Server.MainRoom
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
