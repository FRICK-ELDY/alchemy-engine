defmodule Contents.Components.Category.Network.Osc.Sender do
  @moduledoc """
  指定 URL の OSC サーバへデータを送信するコンポーネント。

  Resonite の [OSC Sender](https://wiki.resonite.com/Component:OSC_Sender) に合わせる。

  ## Fields

  | Name | Type | Description |
  | --- | --- | --- |
  | persistent | Bool | サーバへ保存するか |
  | update_order | Int | 更新順 |
  | enabled | Bool | 有効なら送信する |
  | handling_user | UserRef | OSC サーバを探すユーザ（現状は記録のみ） |
  | access_reason | String | 接続確立時に表示する理由（ログに出力） |
  | url | Uri | `osc://<ip>:<port>`（例: `osc://127.0.0.1:3001`） |
  | local_port | Int | 送信元ポート。`0` は OS 割り当て |
  | is_sending | Bool | 送信可能なとき true |
  | send_mode | OSC_SendMode | `:send_individually` または `:send_as_bundles` |
  | auto_resend_interval | Float | 変更がなくても再送する間隔（秒）。`0` で再送しない |

  値の送信には `OSC_Value` / `OSC_Field` を `Handler` として本プロセスに接続する。

  同一 Path の複数引数は 256 個まで。Headless では URL ホストを `localhost` にする必要がある環境がある
  （Resonite と同様。本実装では `127.0.0.1` も利用可）。
  """
  use GenServer
  @behaviour Contents.Behaviour.ObjectComponent

  alias Contents.Components.Category.Network.Osc.Protocol

  require Logger

  @max_args_per_path 256

  @type send_mode :: :send_individually | :send_as_bundles

  @type t :: %__MODULE__{
          persistent: boolean(),
          update_order: integer(),
          enabled: boolean(),
          handling_user: term() | nil,
          access_reason: String.t(),
          url: String.t(),
          local_port: integer(),
          is_sending: boolean(),
          send_mode: send_mode(),
          auto_resend_interval: float()
        }

  defstruct persistent: true,
            update_order: 0,
            enabled: true,
            handling_user: nil,
            access_reason: "OSC Sender",
            url: "osc://127.0.0.1:9000",
            local_port: 0,
            is_sending: false,
            send_mode: :send_individually,
            auto_resend_interval: 0.0

  @field_keys [
    :persistent,
    :update_order,
    :enabled,
    :handling_user,
    :access_reason,
    :url,
    :local_port,
    :is_sending,
    :send_mode,
    :auto_resend_interval
  ]

  @doc "Resonite 互換のフィールド初期値で構造体を生成する。"
  @spec new(keyword() | map()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, Map.take(Map.new(opts), @field_keys))
  end

  @doc "OSC Sender を起動する。"
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

  @spec connect_error(pid()) :: term() | nil
  def connect_error(pid), do: GenServer.call(pid, :connect_error)

  @spec set_enabled(pid(), boolean()) :: :ok
  def set_enabled(pid, enabled) when is_boolean(enabled) do
    GenServer.call(pid, {:set_enabled, enabled})
  end

  @impl Contents.Behaviour.ObjectComponent
  def run(_object, _context), do: :ok

  @impl GenServer
  def init(opts) do
    fields = new(opts)

    state = %{
      fields: fields,
      socket: nil,
      dest: nil,
      bindings: %{},
      connect_error: nil,
      resend_timer: nil
    }

    {:ok, state |> maybe_connect() |> schedule_resend()}
  end

  @impl GenServer
  def handle_call(:fields, _from, state), do: {:reply, state.fields, state}
  def handle_call(:connect_error, _from, state), do: {:reply, state.connect_error, state}

  def handle_call({:set_enabled, enabled}, _from, state) do
    state =
      state
      |> cancel_resend()
      |> close_socket()
      |> put_fields(%{state.fields | enabled: enabled})
      |> maybe_connect()
      |> schedule_resend()

    {:reply, :ok, state}
  end

  def handle_call({:register_binding, binding}, _from, state) do
    state = add_binding(state, binding)
    send_for_path(state, Map.fetch!(binding, :path))
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:register_binding, binding}, state) do
    state = add_binding(state, binding)
    send_for_path(state, Map.fetch!(binding, :path))
    {:noreply, state}
  end

  def handle_cast({:unregister_binding, pid}, state) when is_pid(pid) do
    bindings =
      state.bindings
      |> Enum.reject(fn {_key, %{pid: binding_pid}} -> binding_pid == pid end)
      |> Map.new()

    {:noreply, %{state | bindings: bindings}}
  end

  def handle_cast({:value_changed, path, argument_index, value}, state) do
    key = {path, argument_index}

    bindings =
      case Map.get(state.bindings, key) do
        nil -> state.bindings
        binding -> Map.put(state.bindings, key, %{binding | last_value: value})
      end

    state = %{state | bindings: bindings}

    case state.fields.send_mode do
      :send_as_bundles -> send_all_as_bundle(state)
      _ -> send_for_path(state, path)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:resend, state) do
    state = %{state | bindings: refresh_bindings(state.bindings)}

    case state.fields.send_mode do
      :send_as_bundles -> send_all_as_bundle(state)
      _ -> send_all_individually(state)
    end

    {:noreply, schedule_resend(state)}
  end

  def handle_info({:udp, _socket, _ip, _port, _data}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    cancel_resend(state)
    close_socket(state)
    :ok
  end

  defp add_binding(state, binding) do
    path = Map.fetch!(binding, :path)
    idx = Map.get(binding, :argument_index, 0)
    key = {path, idx}

    entry = %{
      pid: Map.fetch!(binding, :pid),
      last_value: Map.get(binding, :last_value)
    }

    %{state | bindings: Map.put(state.bindings, key, entry)}
  end

  defp refresh_bindings(bindings) do
    Map.new(bindings, fn {key, %{pid: pid} = binding} ->
      value =
        if Process.alive?(pid) do
          try do
            GenServer.call(pid, :get, 50)
          catch
            :exit, _ -> binding.last_value
          end
        else
          binding.last_value
        end

      {key, %{binding | last_value: value}}
    end)
  end

  defp send_for_path(%{fields: %{enabled: false}}, _path), do: :ok
  defp send_for_path(%{socket: nil}, _path), do: :ok

  defp send_for_path(state, path) do
    case args_for_path(state.bindings, path) do
      [] ->
        :ok

      args ->
        packet = Protocol.encode_message(path, args)
        send_packet(state, packet)
    end
  end

  defp send_all_individually(state) do
    state.bindings
    |> Enum.map(fn {{path, _idx}, _} -> path end)
    |> Enum.uniq()
    |> Enum.each(&send_for_path(state, &1))
  end

  defp send_all_as_bundle(%{fields: %{enabled: false}}), do: :ok
  defp send_all_as_bundle(%{socket: nil}), do: :ok

  defp send_all_as_bundle(state) do
    elements =
      state.bindings
      |> Enum.map(fn {{path, _idx}, _} -> path end)
      |> Enum.uniq()
      |> Enum.flat_map(fn path ->
        case args_for_path(state.bindings, path) do
          [] -> []
          args -> [{path, args}]
        end
      end)

    if elements != [] do
      send_packet(state, Protocol.encode_bundle(elements))
    end
  end

  defp args_for_path(bindings, path) do
    indexed =
      bindings
      |> Enum.filter(fn {{p, _idx}, _} -> p == path end)
      |> Enum.map(fn {{_p, idx}, %{last_value: value}} -> {idx, value} end)

    case indexed do
      [] ->
        []

      list ->
        max_idx = list |> Enum.map(&elem(&1, 0)) |> Enum.max() |> min(@max_args_per_path - 1)
        by_idx = Map.new(list)

        Enum.map(0..max_idx, fn idx ->
          Map.get(by_idx, idx, 0.0)
        end)
    end
  end

  defp send_packet(%{socket: socket, dest: {ip, port}}, packet) do
    :gen_udp.send(socket, ip, port, packet)
  end

  defp send_packet(_, _), do: :ok

  defp maybe_connect(%{fields: %{enabled: false}} = state) do
    put_fields(%{state | dest: nil, connect_error: nil}, %{state.fields | is_sending: false})
  end

  defp maybe_connect(state) do
    with {:ok, {host, port}} <- parse_url(state.fields.url),
         {:ok, ip} <- resolve_host(host),
         {:ok, socket} <-
           :gen_udp.open(state.fields.local_port, [:binary, {:active, true}, {:reuseaddr, true}]),
         {:ok, actual_local} <- :inet.port(socket) do
      Logger.info(
        "[OSC.Sender] #{state.fields.access_reason} sending to #{state.fields.url} (local port #{actual_local})"
      )

      put_fields(
        %{state | socket: socket, dest: {ip, port}, connect_error: nil},
        %{state.fields | is_sending: true, local_port: actual_local}
      )
    else
      {:error, reason} ->
        Logger.warning("[OSC.Sender] failed to connect #{state.fields.url}: #{inspect(reason)}")

        put_fields(
          %{state | socket: nil, dest: nil, connect_error: reason},
          %{state.fields | is_sending: false}
        )
    end
  end

  defp parse_url(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["osc", "udp"] ->
        {:error, :invalid_url}

      is_nil(uri.host) or uri.host == "" ->
        {:error, :invalid_url}

      true ->
        {:ok, {uri.host, uri.port || 9000}}
    end
  end

  defp resolve_host(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        {:ok, ip}

      {:error, _} ->
        :inet.getaddr(String.to_charlist(host), :inet)
    end
  end

  defp schedule_resend(state) do
    state = cancel_resend(state)
    interval_ms = round(state.fields.auto_resend_interval * 1000)

    if state.fields.enabled and interval_ms > 0 do
      timer = Process.send_after(self(), :resend, interval_ms)
      %{state | resend_timer: timer}
    else
      state
    end
  end

  defp cancel_resend(%{resend_timer: timer} = state) when is_reference(timer) do
    Process.cancel_timer(timer)
    %{state | resend_timer: nil}
  end

  defp cancel_resend(state), do: %{state | resend_timer: nil}

  defp close_socket(%{socket: socket} = state) when is_port(socket) do
    :gen_udp.close(socket)
    put_fields(%{state | socket: nil, dest: nil}, %{state.fields | is_sending: false})
  end

  defp close_socket(state),
    do: put_fields(%{state | socket: nil, dest: nil}, %{state.fields | is_sending: false})

  defp put_fields(state, fields), do: %{state | fields: fields}
end
