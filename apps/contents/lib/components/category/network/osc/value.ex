defmodule Contents.Components.Category.Network.Osc.Value do
  @moduledoc """
  OSC の値をコンポーネント自身の `Value` フィールドとして送受信する。

  Resonite の [OSC Value](https://wiki.resonite.com/Component:OSC_Value)（`OSC_Value\`1`）に合わせる。

  ## Fields

  | Name | Type | Description |
  | --- | --- | --- |
  | persistent | Bool | サーバへ保存するか |
  | update_order | Int | 更新順 |
  | enabled | Bool | 有効なら Handler と同期する |
  | handler | OSC_Handler | `OSC_Receiver` または `OSC_Sender` の pid |
  | path | String | OSC Path |
  | argument_index | Int | 複数引数 OSC のうち何番目を扱うか |
  | value | T | 受信値。未受信時は型のデフォルト |

  `Handler` が Receiver のときは `Path` に届いた値を `value` へ書く。
  `Handler` が Sender のときは `value` の変更（および Sender の `AutoResendInterval`）で送信する。
  """
  use GenServer
  @behaviour Contents.Behaviour.ObjectComponent

  @type t :: %__MODULE__{
          persistent: boolean(),
          update_order: integer(),
          enabled: boolean(),
          handler: pid() | nil,
          path: String.t(),
          argument_index: integer(),
          value: term()
        }

  defstruct persistent: true,
            update_order: 0,
            enabled: true,
            handler: nil,
            path: "/",
            argument_index: 0,
            value: 0.0

  @field_keys [
    :persistent,
    :update_order,
    :enabled,
    :handler,
    :path,
    :argument_index,
    :value
  ]

  @doc "Resonite 互換のフィールド初期値で構造体を生成する。"
  @spec new(keyword() | map()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, Map.take(Map.new(opts), @field_keys))
  end

  @doc "OSC Value を起動し、Handler にバインドする。"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} =
      Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @spec stop(pid()) :: :ok
  def stop(pid), do: GenServer.stop(pid)

  @spec get(pid()) :: term()
  def get(pid), do: GenServer.call(pid, :get)

  @spec set(pid(), term()) :: :ok
  def set(pid, value), do: GenServer.call(pid, {:set, value})

  @spec fields(pid()) :: t()
  def fields(pid), do: GenServer.call(pid, :fields)

  @impl Contents.Behaviour.ObjectComponent
  def run(_object, _context), do: :ok

  @impl GenServer
  def init(opts) do
    state = new(opts)
    register(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get, _from, state), do: {:reply, state.value, state}
  def handle_call(:fields, _from, state), do: {:reply, state, state}

  def handle_call({:set, value}, _from, state) do
    state = %{state | value: value}
    notify_handler(state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:osc_received, path, args, idx}, %{path: path, argument_index: idx} = state) do
    {:noreply, %{state | value: Enum.at(args, idx, state.value)}}
  end

  def handle_info({:osc_received, _path, _args, _idx}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    unregister(state)
    :ok
  end

  defp register(%{handler: pid, enabled: true} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.cast(pid, {:register_binding, osc_binding(state)})
    end
  end

  defp register(_), do: :ok

  defp unregister(%{handler: pid} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.cast(pid, {:unregister_binding, self()})
    end

    state
  end

  defp unregister(state), do: state

  defp notify_handler(%{handler: pid, enabled: true} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.cast(pid, {:value_changed, state.path, state.argument_index, state.value})
    end
  end

  defp notify_handler(_), do: :ok

  defp osc_binding(state) do
    %{
      pid: self(),
      path: state.path,
      argument_index: state.argument_index,
      last_value: state.value
    }
  end
end
