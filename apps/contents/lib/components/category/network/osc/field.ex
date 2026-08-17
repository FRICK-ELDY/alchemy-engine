defmodule Contents.Components.Category.Network.Osc.Field do
  @moduledoc """
  OSC の値を別フィールド（`IField` 相当）へ読み書きするコンポーネント。

  Resonite の [OSC Field](https://wiki.resonite.com/Component:OSC_Field)（`OSC_Field\`1`）に合わせる。

  ## Fields

  | Name | Type | Description |
  | --- | --- | --- |
  | persistent | Bool | サーバへ保存するか |
  | update_order | Int | 更新順 |
  | enabled | Bool | 有効なら Handler と同期する |
  | handler | OSC_Handler | `OSC_Receiver` または `OSC_Sender` の pid |
  | path | String | OSC Path |
  | argument_index | Int | 複数引数 OSC のうち何番目を扱うか |
  | field | RelayRef\\<IField\\<T\\>\\> | 値の格納先。`{:agent, pid}` / `pid` / `{:ets, table, key}` |

  `Handler` が Receiver のときは OSC 値を `field` へ書く。
  `Handler` が Sender のときは `field` の値を読み出して送信する。
  """
  use GenServer
  @behaviour Contents.Behaviour.ObjectComponent

  @type field_ref ::
          {:agent, pid()}
          | pid()
          | {:ets, atom() | :ets.tid(), term()}
          | nil

  @type t :: %__MODULE__{
          persistent: boolean(),
          update_order: integer(),
          enabled: boolean(),
          handler: pid() | nil,
          path: String.t(),
          argument_index: integer(),
          field: field_ref()
        }

  defstruct persistent: true,
            update_order: 0,
            enabled: true,
            handler: nil,
            path: "/",
            argument_index: 0,
            field: nil

  @field_keys [
    :persistent,
    :update_order,
    :enabled,
    :handler,
    :path,
    :argument_index,
    :field
  ]

  @doc "Resonite 互換のフィールド初期値で構造体を生成する。"
  @spec new(keyword() | map()) :: t()
  def new(opts \\ []) do
    opts
    |> Map.new()
    |> Map.take(@field_keys)
    |> Map.update(:field, nil, &normalize_field/1)
    |> then(&struct(__MODULE__, &1))
  end

  @doc "OSC Field を起動し、Handler にバインドする。"
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
  def handle_call(:get, _from, state), do: {:reply, read_field(state.field), state}
  def handle_call(:fields, _from, state), do: {:reply, state, state}

  def handle_call({:set, value}, _from, state) do
    write_field(state.field, value)
    notify_handler(state, value)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:osc_received, path, args, idx}, %{path: path, argument_index: idx} = state) do
    value = Enum.at(args, idx, read_field(state.field))
    write_field(state.field, value)
    {:noreply, state}
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

  defp unregister(%{handler: pid}) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.cast(pid, {:unregister_binding, self()})
    end
  end

  defp unregister(_), do: :ok

  defp notify_handler(%{handler: pid, enabled: true} = state, value) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.cast(pid, {:value_changed, state.path, state.argument_index, value})
    end
  end

  defp notify_handler(_, _), do: :ok

  defp osc_binding(state) do
    %{
      pid: self(),
      path: state.path,
      argument_index: state.argument_index,
      last_value: read_field(state.field)
    }
  end

  defp normalize_field(nil), do: nil
  defp normalize_field(pid) when is_pid(pid), do: {:agent, pid}
  defp normalize_field({:agent, pid} = ref) when is_pid(pid), do: ref
  defp normalize_field({:ets, _table, _key} = ref), do: ref

  defp read_field(nil), do: nil

  defp read_field({:agent, pid}) do
    if Process.alive?(pid), do: Agent.get(pid, & &1), else: nil
  end

  defp read_field({:ets, table, key}) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      _ -> nil
    end
  end

  defp write_field(nil, _value), do: :ok
  defp write_field({:agent, pid}, value), do: Agent.update(pid, fn _ -> value end)
  defp write_field({:ets, table, key}, value), do: :ets.insert(table, {key, value})
end
