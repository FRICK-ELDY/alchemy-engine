defmodule Contents.Components.Category.Network.Osc.Receiver do
  @moduledoc """
  OSC サーバを開き、UDP で OSC メッセージを受信するコンポーネント。

  Resonite の [OSC Receiver](https://wiki.resonite.com/Component:OSC_Receiver) に合わせる。

  ## Fields

  | Name | Type | Description |
  | --- | --- | --- |
  | persistent | Bool | サーバへ保存するか |
  | update_order | Int | 更新順 |
  | enabled | Bool | 有効なら待受する。期待どおり動かないときは無効化→再有効化を試す |
  | handling_user | UserRef | OSC サーバを開くユーザ（現状は記録のみ） |
  | access_reason | String | 接続確立時に表示する理由（ログに出力） |
  | port | Int | 待受 UDP ポート。`0` は OS 割り当て |
  | is_listening | Bool | 待受に成功すると true |

  受信した値の取り出しには `OSC_Value` / `OSC_Field` を `Handler` として本プロセスに接続する。
  """
  use GenServer
  @behaviour Contents.Behaviour.ObjectComponent

  alias Contents.Components.Category.Network.Osc.Protocol

  require Logger

  @type t :: %__MODULE__{
          persistent: boolean(),
          update_order: integer(),
          enabled: boolean(),
          handling_user: term() | nil,
          access_reason: String.t(),
          port: integer(),
          is_listening: boolean()
        }

  defstruct persistent: true,
            update_order: 0,
            enabled: true,
            handling_user: nil,
            access_reason: "OSC Receiver",
            port: 9000,
            is_listening: false

  @field_keys [
    :persistent,
    :update_order,
    :enabled,
    :handling_user,
    :access_reason,
    :port,
    :is_listening
  ]

  @doc "Resonite 互換のフィールド初期値で構造体を生成する。"
  @spec new(keyword() | map()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, Map.take(Map.new(opts), @field_keys))
  end

  @doc "OSC Receiver を起動する。"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} =
      Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @spec stop(pid()) :: :ok
  def stop(pid), do: GenServer.stop(pid)

  @spec fields(pid()) :: t()
  def fields(pid), do: GenServer.call(pid, :fields)

  @spec listen_error(pid()) :: term() | nil
  def listen_error(pid), do: GenServer.call(pid, :listen_error)

  @doc """
  最後に受信したパケット。未受信時は `nil`。

  成功時: `%{path: String.t(), args: list(), from: {ip, port}}`
  デコード失敗時: `%{invalid: true, byte_size: non_neg_integer(), from: {ip, port}}`
  """
  @spec last_packet(pid()) :: map() | nil
  def last_packet(pid), do: GenServer.call(pid, :last_packet)

  @spec set_enabled(pid(), boolean()) :: :ok
  def set_enabled(pid, enabled) when is_boolean(enabled) do
    GenServer.call(pid, {:set_enabled, enabled})
  end

  @spec set_port(pid(), integer()) :: :ok
  def set_port(pid, port) when is_integer(port) and port >= 0 do
    GenServer.call(pid, {:set_port, port})
  end

  @impl Contents.Behaviour.ObjectComponent
  def run(_object, _context), do: :ok

  @impl GenServer
  def init(opts) do
    fields = new(opts)

    state = %{
      fields: fields,
      socket: nil,
      bindings: %{},
      listen_error: nil,
      last_packet: nil
    }

    {:ok, maybe_listen(state)}
  end

  @impl GenServer
  def handle_call(:fields, _from, state), do: {:reply, state.fields, state}
  def handle_call(:listen_error, _from, state), do: {:reply, state.listen_error, state}
  def handle_call(:last_packet, _from, state), do: {:reply, state.last_packet, state}

  def handle_call({:set_enabled, enabled}, _from, state) do
    state =
      state
      |> close_socket()
      |> put_fields(%{state.fields | enabled: enabled})
      |> maybe_listen()

    {:reply, :ok, state}
  end

  def handle_call({:set_port, port}, _from, state) do
    state =
      state
      |> close_socket()
      |> put_fields(%{state.fields | port: port})
      |> maybe_listen()

    {:reply, :ok, state}
  end

  def handle_call({:register_binding, binding}, _from, state) do
    {:reply, :ok, add_binding(state, binding)}
  end

  @impl GenServer
  def handle_cast({:register_binding, binding}, state) do
    {:noreply, add_binding(state, binding)}
  end

  def handle_cast({:unregister_binding, pid}, state) when is_pid(pid) do
    bindings =
      Map.new(state.bindings, fn {path, list} ->
        {path, Enum.reject(list, &(&1.pid == pid))}
      end)

    {:noreply, %{state | bindings: bindings}}
  end

  def handle_cast({:value_changed, _path, _idx, _value}, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({:udp, socket, ip, src_port, data}, %{socket: socket} = state) do
    from = {ip, src_port}

    state =
      case Protocol.decode(data) do
        {:ok, packet} ->
          record_and_dispatch(state, packet, from)

        {:error, :invalid} ->
          Logger.warning(
            "[OSC.Receiver] invalid packet from #{format_from(from)} size=#{byte_size(data)}"
          )

          %{state | last_packet: %{invalid: true, byte_size: byte_size(data), from: from}}
      end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    close_socket(state)
    :ok
  end

  defp add_binding(state, binding) do
    path = Map.fetch!(binding, :path)

    entry = %{
      pid: Map.fetch!(binding, :pid),
      argument_index: Map.get(binding, :argument_index, 0)
    }

    bindings = Map.update(state.bindings, path, [entry], &[entry | &1])
    %{state | bindings: bindings}
  end

  defp record_and_dispatch(state, {:message, path, args}, from) do
    Logger.info("[OSC.Receiver] #{path} #{inspect(args)} from #{format_from(from)}")
    dispatch_message(state, path, args)
    %{state | last_packet: %{path: path, args: args, from: from}}
  end

  defp record_and_dispatch(state, {:bundle, _timetag, elements}, from) do
    Enum.reduce(elements, state, fn element, acc ->
      record_and_dispatch(acc, element, from)
    end)
  end

  defp dispatch_message(state, path, args) do
    Enum.each(Map.get(state.bindings, path, []), fn %{pid: pid, argument_index: idx} ->
      if Process.alive?(pid), do: send(pid, {:osc_received, path, args, idx})
    end)
  end

  defp format_from({{a, b, c, d}, port}), do: "#{a}.#{b}.#{c}.#{d}:#{port}"
  defp format_from({ip, port}), do: "#{inspect(ip)}:#{port}"

  defp maybe_listen(%{fields: %{enabled: false}} = state) do
    %{state | listen_error: nil}
  end

  defp maybe_listen(state) do
    case :gen_udp.open(state.fields.port, [
           :binary,
           {:active, true},
           {:reuseaddr, true},
           {:ip, {0, 0, 0, 0}}
         ]) do
      {:ok, socket} ->
        {:ok, actual_port} = :inet.port(socket)

        Logger.info(
          "[OSC.Receiver] #{state.fields.access_reason} listening on UDP 0.0.0.0:#{actual_port}"
        )

        %{
          state
          | socket: socket,
            listen_error: nil,
            fields: %{state.fields | is_listening: true, port: actual_port}
        }

      {:error, reason} ->
        Logger.warning(
          "[OSC.Receiver] failed to listen on port #{state.fields.port}: #{inspect(reason)}"
        )

        %{
          state
          | socket: nil,
            listen_error: reason,
            fields: %{state.fields | is_listening: false}
        }
    end
  end

  defp close_socket(%{socket: socket} = state) when is_port(socket) do
    :gen_udp.close(socket)
    %{state | socket: nil, fields: %{state.fields | is_listening: false}}
  end

  defp close_socket(state),
    do: %{state | socket: nil, fields: %{state.fields | is_listening: false}}

  defp put_fields(state, fields), do: %{state | fields: fields}
end
