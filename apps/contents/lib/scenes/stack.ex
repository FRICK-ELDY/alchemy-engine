defmodule Contents.Scenes.Stack do
  @moduledoc """
  シーンスタックを管理する GenServer。

  シーンは `%{scene_type: scene_type(), state: term()}` で表現し、
  push / pop によりスタックで管理する。初期化・更新は content の
  `scene_init/2`, `scene_update/3`, `scene_render_type/1` で行う。

  state の構造は Content に委ねる。推奨規約（origin / landing_object / children）は
  `Contents.Scenes` の `@type recommended_state` および
  docs/architecture/scene-and-object.md を参照。

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

  @doc """
  現在トップのシーンの state を、fun の返り値で置き換える。

  fun の引数はスタックに保存されている **state そのもの**。
  ファサード利用 Content では state は `%{scene_module: mod, inner_state: inner}` のラップ済みなので、
  「現在の inner state を引数に取り更新する」ような fun を渡す場合はラップ構造を意識すること。
  """
  def update_current(server \\ default_server(), fun) when is_function(fun, 1) do
    GenServer.call(server, {:update_current, fun})
  end

  def update_by_scene_type(server \\ default_server(), scene_type, fun)
      when is_function(fun, 1) do
    GenServer.call(server, {:update_by_scene_type, scene_type, fun})
  end

  @doc """
  指定した scene_type のシーンの state を返す（unwrap 済みの inner state）。

  該当シーンがスタックに無い場合は `%{}` を返す。このため「シーンが存在しない」と
  「シーンはあるが state が空 map」は区別できない。区別が必要な場合は将来 nil を返す API の検討余地がある。
  """
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

  def handle_call(
        {:push, scene_type, init_arg},
        _from,
        %{stack: stack, content_module: content} = state
      ) do
    {:ok, scene} = init_scene(content, scene_type, init_arg)
    {:reply, :ok, %{state | stack: [scene | stack]}}
  end

  def handle_call(:pop, _from, %{stack: [_]} = state) do
    {:reply, {:error, :cannot_pop_root}, state}
  end

  def handle_call(:pop, _from, %{stack: [_top | rest]} = state) do
    {:reply, :ok, %{state | stack: rest}}
  end

  def handle_call(
        {:replace, scene_type, init_arg},
        _from,
        %{stack: [_ | rest], content_module: content} = state
      ) do
    {:ok, scene} = init_scene(content, scene_type, init_arg)
    {:reply, :ok, %{state | stack: [scene | rest]}}
  end

  def handle_call(
        {:replace, scene_type, init_arg},
        _from,
        %{stack: [], content_module: content} = state
      ) do
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
    case Enum.with_index(stack) |> Enum.find(fn {s, _idx} -> s.scene_type == scene_type end) do
      nil ->
        {:reply, :ok, state}

      {scene, index} ->
        inner = unwrap_scene_state(scene.state)
        new_inner = fun.(inner)
        new_state = wrap_scene_state(scene.state, new_inner)
        new_scene = %{scene | state: new_state}
        new_stack = List.replace_at(stack, index, new_scene)
        {:reply, :ok, %{state | stack: new_stack}}
    end
  end

  def handle_call({:get_scene_state, scene_type}, _from, %{stack: stack} = state) do
    scene_state =
      case Enum.find(stack, fn scene -> scene.scene_type == scene_type end) do
        %{state: s} -> unwrap_scene_state(s)
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

  # Contents.Scenes ファサード経由で init した場合、state は %{scene_module: mod, inner_state: inner} で包まれる。
  # get_scene_state / update_by_scene_type の呼び出し元は inner を期待するため、ラップの有無で出し分ける。
  defp unwrap_scene_state(%{scene_module: _mod, inner_state: inner}), do: inner
  defp unwrap_scene_state(other), do: other

  defp wrap_scene_state(%{scene_module: mod, inner_state: _}, new_inner),
    do: %{scene_module: mod, inner_state: new_inner}

  defp wrap_scene_state(_, new_inner), do: new_inner
end
