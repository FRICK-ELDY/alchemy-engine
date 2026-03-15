defmodule Contents.Scenes.Stack do
  @moduledoc """
  シーンスタックを管理する GenServer。

  シーンは `%{scene_type: scene_type(), state: term()}` で表現し、
  push / pop によりスタックで管理する。初期化・更新は content の
  `scene_init/2`, `scene_update/3`, `scene_render_type/1` で行う。

  ## オプション

  - `:content_module` (必須) - シーン構成を提供するコンテンツモジュール（`initial_scenes/0`, `scene_*` を実装）
  - `:room_id` (オプション) - マルチルーム対応用。指定時は `{__MODULE__, room_id}` で名前登録される
  - `:name` (オプション) - GenServer の登録名。`room_id` 未指定時のみ使用。省略時は `__MODULE__`

  ## 例

      # 単一ルーム（content_module 指定）
      Contents.Scenes.Stack.start_link(content_module: Content.VampireSurvivor)

      # マルチルーム準備（room_id 指定）
      Contents.Scenes.Stack.start_link(
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

  def push_scene(server \\ default_server(), scene_type, init_arg \\ %{}) do
    GenServer.call(server, {:push, scene_type, init_arg})
  end

  def pop_scene(server \\ default_server()) do
    GenServer.call(server, :pop)
  end

  def replace_scene(server \\ default_server(), scene_type, init_arg \\ %{}) do
    GenServer.call(server, {:replace, scene_type, init_arg})
  end

  def update_current(server \\ default_server(), fun) when is_function(fun, 1) do
    GenServer.call(server, {:update_current, fun})
  end

  def update_by_scene_type(server \\ default_server(), scene_type, fun) when is_function(fun, 1) do
    GenServer.call(server, {:update_by_scene_type, scene_type, fun})
  end

  def get_scene_state(server \\ default_server(), scene_type) do
    GenServer.call(server, {:get_scene_state, scene_type})
  end

  # initial_scenes の各 spec で scene_init を呼ぶ。scene_init が {:ok, _} 以外を返すか raise すると init 全体が失敗する。
  @impl true
  def init(opts) do
    content_module = Keyword.fetch!(opts, :content_module)
    specs = content_module.initial_scenes()

    stack =
      Enum.reduce(specs, [], fn spec, acc ->
        {:ok, scene} = init_scene(content_module, spec.scene_type, spec.init_arg)
        [scene | acc]
      end)

    default_render_type =
      case stack do
        [top | _] -> content_module.scene_render_type(top.scene_type)
        [] -> content_module.scene_render_type(Keyword.get(opts, :default_scene_type, :playing))
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

  def handle_call(:render_type, _from, %{stack: [], default_render_type: rt} = state) do
    {:reply, rt, state}
  end

  def handle_call(:render_type, _from, %{stack: [top | _], content_module: content} = state) do
    {:reply, content.scene_render_type(top.scene_type), state}
  end

  def handle_call({:push, scene_type, init_arg}, _from, %{stack: stack, content_module: content} = state) do
    {:ok, scene} = init_scene(content, scene_type, init_arg)
    {:reply, :ok, %{state | stack: [scene | stack]}}
  end

  def handle_call(:pop, _from, %{stack: [_]} = state) do
    {:reply, {:error, :cannot_pop_root}, state}
  end

  def handle_call(:pop, _from, %{stack: [_top | rest]} = state) do
    {:reply, :ok, %{state | stack: rest}}
  end

  def handle_call({:replace, scene_type, init_arg}, _from, %{stack: [_ | rest], content_module: content} = state) do
    {:ok, scene} = init_scene(content, scene_type, init_arg)
    {:reply, :ok, %{state | stack: [scene | rest]}}
  end

  def handle_call({:replace, scene_type, init_arg}, _from, %{stack: [], content_module: content} = state) do
    {:ok, scene} = init_scene(content, scene_type, init_arg)
    {:reply, :ok, %{state | stack: [scene]}}
  end

  def handle_call({:update_current, _fun}, _from, %{stack: []} = state) do
    {:reply, {:error, :empty}, state}
  end

  def handle_call({:update_current, fun}, _from, %{stack: [top | rest]} = state) do
    new_state = fun.(top.state)
    new_top = %{top | state: new_state}
    {:reply, :ok, %{state | stack: [new_top | rest]}}
  end

  def handle_call({:update_by_scene_type, scene_type, fun}, _from, %{stack: stack} = state) do
    case Enum.find_index(stack, &(&1.scene_type == scene_type)) do
      nil ->
        {:reply, :ok, state}

      index ->
        scene = Enum.at(stack, index)
        new_scene = %{scene | state: fun.(scene.state)}
        new_stack = List.replace_at(stack, index, new_scene)
        {:reply, :ok, %{state | stack: new_stack}}
    end
  end

  def handle_call({:get_scene_state, scene_type}, _from, %{stack: stack} = state) do
    scene_state =
      case Enum.find(stack, fn scene -> scene.scene_type == scene_type end) do
        %{state: s} -> s
        nil -> %{}
      end

    {:reply, scene_state, state}
  end

  defp init_scene(content, scene_type, init_arg) do
    {:ok, scene_state} = content.scene_init(scene_type, init_arg)
    {:ok, %{scene_type: scene_type, state: scene_state}}
  end

  defp resolve_name(opts) do
    cond do
      room_id = Keyword.get(opts, :room_id) -> {__MODULE__, room_id}
      name = Keyword.get(opts, :name) -> name
      true -> __MODULE__
    end
  end

  defp default_server do
    # 単一 Stack は __MODULE__ で登録。マルチルーム時は呼び出し元が {__MODULE__, room_id} を明示的に渡す。
    __MODULE__
  end
end
