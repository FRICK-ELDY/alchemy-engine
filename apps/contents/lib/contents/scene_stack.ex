defmodule Contents.SceneStack do
  @moduledoc """
  シーンスタックを管理する GenServer。

  シーンは `%{module: module(), state: term()}` で表現し、
  push / pop によりスタックで管理する。

  ## オプション

  - `:content_module` (必須) - シーン構成を提供するコンテンツモジュール（`initial_scenes/0`, `render_type/0` を実装）
  - `:room_id` (オプション) - マルチルーム対応用。指定時は `{__MODULE__, room_id}` で名前登録される
  - `:name` (オプション) - GenServer の登録名。`room_id` 未指定時のみ使用。省略時は `__MODULE__`

  ## 例

      # 単一ルーム（content_module 指定）
      Contents.SceneStack.start_link(content_module: Content.VampireSurvivor)

      # マルチルーム準備（room_id 指定）
      Contents.SceneStack.start_link(
        content_module: Content.VampireSurvivor,
        room_id: "room-1"
      )
  """

  use GenServer

  def start_link(opts) do
    name = resolve_name(opts)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def current(server \\ default_server()) do
    GenServer.call(server, :current)
  end

  def render_type(server \\ default_server()) do
    GenServer.call(server, :render_type)
  end

  def push_scene(server \\ default_server(), module, init_arg \\ %{}) do
    GenServer.call(server, {:push, module, init_arg})
  end

  def pop_scene(server \\ default_server()) do
    GenServer.call(server, :pop)
  end

  def replace_scene(server \\ default_server(), module, init_arg \\ %{}) do
    GenServer.call(server, {:replace, module, init_arg})
  end

  def update_current(server \\ default_server(), fun) when is_function(fun, 1) do
    GenServer.call(server, {:update_current, fun})
  end

  def update_by_module(server \\ default_server(), module, fun) when is_function(fun, 1) do
    GenServer.call(server, {:update_by_module, module, fun})
  end

  def get_scene_state(server \\ default_server(), module) do
    GenServer.call(server, {:get_scene_state, module})
  end

  @impl true
  def init(opts) do
    content_module = Keyword.fetch!(opts, :content_module)
    specs = content_module.initial_scenes()

    stack =
      Enum.reduce(specs, [], fn spec, acc ->
        {:ok, scene} = init_scene(spec.module, spec.init_arg)
        [scene | acc]
      end)

    default_render_type =
      case stack do
        [top | _] -> top.module.render_type()
        [] -> content_module.render_type()
      end

    state = %{
      stack: stack,
      default_render_type: default_render_type,
      content_module: content_module
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:current, _from, %{stack: []} = state) do
    {:reply, :empty, state}
  end

  def handle_call(:current, _from, %{stack: [top | _]} = state) do
    {:reply, {:ok, top}, state}
  end

  def handle_call(:render_type, _from, %{stack: [], content_module: content} = state) do
    {:reply, content.render_type(), state}
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
    case Enum.find_index(stack, &(&1.module == module)) do
      nil ->
        {:reply, :ok, state}

      index ->
        scene = Enum.at(stack, index)
        new_scene = %{scene | state: fun.(scene.state)}
        new_stack = List.replace_at(stack, index, new_scene)
        {:reply, :ok, %{state | stack: new_stack}}
    end
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

  defp resolve_name(opts) do
    cond do
      room_id = Keyword.get(opts, :room_id) -> {__MODULE__, room_id}
      name = Keyword.get(opts, :name) -> name
      true -> __MODULE__
    end
  end

  defp default_server do
    # Phase 1: 単一 SceneStack は __MODULE__ で登録。
    # マルチルーム時は呼び出し元が {__MODULE__, room_id} を明示的に渡す。
    __MODULE__
  end
end
