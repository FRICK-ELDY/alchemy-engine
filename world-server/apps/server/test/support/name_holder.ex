defmodule Server.RoomsTest.NameHolder do
  @moduledoc false
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [], name: Contents.Events.Game)
  end

  @impl true
  def init(_) do
    Process.send_after(self(), :release, 200)
    {:ok, []}
  end

  @impl true
  def handle_info(:release, state) do
    {:stop, :normal, state}
  end
end
