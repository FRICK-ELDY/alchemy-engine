defmodule GameEngine.SceneManager do
  @moduledoc """
  シーンスタックを管理する GenServer。

  シーンは `%{module: module(), state: term()}` で表現し、
  push / pop によりスタックで管理する。
  """

  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def current do
    GenServer.call(__MODULE__, :current)
  end

  def render_type do
    GenServer.call(__MODULE__, :render_type)
  end

  def push_scene(module, init_arg \\ %{}) do
    GenServer.call(__MODULE__, {:push, module, init_arg})
  end

  def pop_scene do
    GenServer.call(__MODULE__, :pop)
  end

  def replace_scene(module, init_arg \\ %{}) do
    GenServer.call(__MODULE__, {:replace, module, init_arg})
  end

  def update_current(fun) when is_function(fun, 1) do
    GenServer.call(__MODULE__, {:update_current, fun})
  end

  def update_by_module(module, fun) when is_function(fun, 1) do
    GenServer.call(__MODULE__, {:update_by_module, module, fun})
  end

  def get_scene_state(module) do
    GenServer.call(__MODULE__, {:get_scene_state, module})
  end

  @impl true
  def init(_opts) do
    game_module = Application.get_env(:game_server, :current_game, GameContent.VampireSurvivor)
    specs = game_module.initial_scenes()

    stack =
      Enum.reduce(specs, [], fn spec, acc ->
        {:ok, scene} = init_scene(spec.module, spec.init_arg)
        [scene | acc]
      end)

    default_render_type =
      case stack do
        [top | _] -> top.module.render_type()
        [] -> :playing
      end

    {:ok, %{stack: stack, default_render_type: default_render_type}}
  end

  @impl true
  def handle_call(:current, _from, %{stack: []} = state) do
    {:reply, :empty, state}
  end

  def handle_call(:current, _from, %{stack: [top | _]} = state) do
    {:reply, {:ok, top}, state}
  end

  def handle_call(:render_type, _from, %{stack: []} = state) do
    game = Application.get_env(:game_server, :current_game, GameContent.VampireSurvivor)
    {:reply, game.render_type(), state}
  end

  def handle_call(:render_type, _from, %{stack: [%{module: mod} | _]} = state) do
    {:reply, mod.render_type(), state}
  end

  def handle_call({:push, module, init_arg}, _from, %{stack: stack} = state) do
    {:ok, scene} = init_scene(module, init_arg)
    {:reply, :ok, %{state | stack: [scene | stack]}}
  end

  def handle_call(:pop, _from, %{stack: [_]} = state) do
    {:reply, {:error, :cannot_pop_root}, state}
  end

  def handle_call(:pop, _from, %{stack: [_top | rest]} = state) do
    {:reply, :ok, %{state | stack: rest}}
  end

  def handle_call({:replace, module, init_arg}, _from, %{stack: [_ | rest]} = state) do
    {:ok, scene} = init_scene(module, init_arg)
    {:reply, :ok, %{state | stack: [scene | rest]}}
  end

  def handle_call({:replace, module, init_arg}, _from, %{stack: []} = state) do
    {:ok, scene} = init_scene(module, init_arg)
    {:reply, :ok, %{state | stack: [scene]}}
  end

  def handle_call({:update_current, fun}, _from, %{stack: [top | rest]} = state) do
    new_state = fun.(top.state)
    new_top = %{top | state: new_state}
    {:reply, :ok, %{state | stack: [new_top | rest]}}
  end

  def handle_call({:update_by_module, module, fun}, _from, %{stack: stack} = state) do
    new_stack =
      Enum.map(stack, fn scene ->
        if scene.module == module do
          %{scene | state: fun.(scene.state)}
        else
          scene
        end
      end)
    {:reply, :ok, %{state | stack: new_stack}}
  end

  def handle_call({:get_scene_state, module}, _from, %{stack: stack} = state) do
    scene_state =
      case Enum.find(stack, fn scene -> scene.module == module end) do
        %{state: s} -> s
        nil -> %{}
      end
    {:reply, scene_state, state}
  end

  defp init_scene(module, init_arg) do
    {:ok, scene_state} = module.init(init_arg)
    {:ok, %{module: module, state: scene_state}}
  end
end
