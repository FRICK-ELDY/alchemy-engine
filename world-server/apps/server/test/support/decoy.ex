defmodule Server.RoomsTest.Decoy do
  @moduledoc false
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_) do
    :ok = Core.RoomRegistry.register(:main)
    Process.send_after(self(), :release, 200)
    {:ok, []}
  end

  @impl true
  def handle_info(:release, state) do
    Core.RoomRegistry.unregister(:main)
    {:stop, :normal, state}
  end
end
