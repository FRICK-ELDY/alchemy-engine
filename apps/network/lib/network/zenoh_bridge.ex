defmodule Network.ZenohBridge do
  @moduledoc """
  Zenoh によるサーバー側トランスポート（フェーズ 3）。

  - フレーム publish: `game/room/{room_id}/frame`
  - movement/action subscribe: `game/room/*/input/movement`, `game/room/*/input/action`
  - client_info subscribe: `contents/room/*/client/info` → `:client_info` ETS に保存
  - 受信した入力は `Contents.Events.Game` へ `{:move_input, dx, dy}` / `{:ui_action, name}` で配送

  入力ペイロードの解釈は **protobuf**（movement / action / client_info）。

  設定: `config :network, :zenoh_enabled, true` で有効化。
  """

  use GenServer
  require Logger

  # Zenoh key 形式
  @frame_key "game/room"

  # ワイルドカード購読用
  @movement_selector "game/room/*/input/movement"
  @action_selector "game/room/*/input/action"
  @client_info_selector "contents/room/*/client/info"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  フレームを Zenoh で publish する。
  GenServer.cast で非同期実行（60Hz を考慮）。
  """
  def publish_frame(room_id, frame_binary) when is_binary(frame_binary) do
    GenServer.cast(__MODULE__, {:publish_frame, normalize_room_id(room_id), frame_binary})
  end

  defp normalize_room_id(:main), do: "main"
  defp normalize_room_id(id) when is_binary(id), do: id
  defp normalize_room_id(id) when is_atom(id), do: Atom.to_string(id)

  # ── GenServer ────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    case Zenohex.Session.open(zenoh_config()) do
      {:ok, session_id} ->
        ensure_client_info_table()

        # movement / action / client_info の subscriber を登録（自プロセスにメッセージ配送）
        # 注意: Zenohex は subscriber_id を保持しないと GC でドロップされるため state に格納する
        {:ok, mov_sub} =
          Zenohex.Session.declare_subscriber(session_id, @movement_selector, self())

        {:ok, act_sub} = Zenohex.Session.declare_subscriber(session_id, @action_selector, self())

        {:ok, info_sub} =
          Zenohex.Session.declare_subscriber(session_id, @client_info_selector, self())

        Logger.info(
          "[ZenohBridge] Started, frame publish + movement/action/client_info subscribe"
        )

        Logger.info("[input:ZenohBridge] init: subscribed to movement=#{@movement_selector}")

        {:ok,
         %{
           session_id: session_id,
           mov_sub: mov_sub,
           act_sub: act_sub,
           info_sub: info_sub
         }}

      {:error, reason} ->
        Logger.error("[ZenohBridge] Failed to open session: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp zenoh_config do
    case Application.get_env(:network, :zenoh_config) do
      nil ->
        # zenoh_connect が指定されていれば client モードで zenohd に接続
        case Application.get_env(:network, :zenoh_connect) do
          nil ->
            Zenohex.Config.default()

          "" ->
            Zenohex.Config.default()

          connect ->
            # mode: client, connect.endpoints を設定して zenohd に明示接続
            Jason.encode!(%{
              "mode" => "client",
              "connect" => %{"endpoints" => [connect]}
            })
        end

      config ->
        config
    end
  end

  @impl true
  def handle_cast({:publish_frame, room_id, frame_binary}, state) do
    key = "#{@frame_key}/#{room_id}/frame"

    case Zenohex.Session.put(state.session_id, key, frame_binary, put_opts()) do
      :ok ->
        # デバッグ: 初回 5 回 + 以降 60 フレームに 1 回
        count = :persistent_term.get({__MODULE__, :publish_count}, 0) + 1
        :persistent_term.put({__MODULE__, :publish_count}, count)

        if count <= 5 or rem(count, 60) == 1 do
          Logger.info(
            "[ZenohBridge] publish ok key=#{key} size=#{byte_size(frame_binary)} count=#{count}"
          )
        end

        :ok

      {:error, reason} ->
        Logger.warning("[ZenohBridge] publish_frame failed room=#{room_id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp put_opts do
    # 60Hz フレームは CongestionControl::Drop で古いフレームをドロップ
    [congestion_control: :drop]
  end

  @impl true
  def handle_info(%Zenohex.Sample{key_expr: key_expr, payload: payload, kind: kind}, state) do
    parsed = parse_input_key(key_expr)

    if kind != :put do
      Logger.warning(
        "[input:ZenohBridge] Sample kind is not :put (got #{inspect(kind)}), skipping"
      )
    else
      case parsed do
        {:movement, room_id} ->
          handle_movement(room_id, payload)

        {:action, room_id} ->
          handle_action(room_id, payload)

        {:client_info, room_id} ->
          handle_client_info(room_id, payload)

        :unknown ->
          Logger.debug("[input:ZenohBridge] Unknown key_expr=#{key_expr}")
      end
    end

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("[input:ZenohBridge] handle_info UNMATCHED msg=#{inspect(msg, limit: 3)}")
    {:noreply, state}
  end

  defp parse_input_key(key_expr) do
    # "game/room/main/input/movement" -> {:movement, "main"}
    # "contents/room/main/client/info" -> {:client_info, "main"}
    parts = String.split(key_expr, "/")

    case parts do
      ["contents", "room", room_id, "client", "info"] ->
        {:client_info, room_id}

      ["game", "room", room_id | _rest] ->
        suffix = Enum.drop(parts, 3) |> Enum.join("/")

        cond do
          suffix == "input/movement" -> {:movement, room_id}
          suffix == "input/action" -> {:action, room_id}
          true -> :unknown
        end

      _ ->
        :unknown
    end
  end

  defp handle_movement(room_id, payload) do
    case decode_movement(payload) do
      {:ok, {dx, dy}} ->
        forward_move_input(room_id, dx, dy)

      :error ->
        Logger.warning("[input:ZenohBridge] handle_movement decode error room=#{room_id}")
    end
  end

  defp decode_movement(payload) do
    case try_decode_movement_protobuf(payload) do
      {:ok, {dx, dy}} -> {:ok, {dx * 1.0, dy * 1.0}}
      {:error, _} -> :error
    end
  end

  defp handle_action(room_id, payload) do
    case decode_action(payload) do
      {:ok, name} ->
        forward_ui_action(room_id, name)

      :error ->
        Logger.warning("[input:ZenohBridge] Invalid action payload room=#{room_id}")
    end
  end

  defp decode_action(payload) do
    case try_decode_action_protobuf(payload) do
      {:ok, name} when is_binary(name) -> {:ok, name}
      {:error, _} -> :error
    end
  end

  defp forward_move_input(room_id, dx, dy) do
    room_key = room_id_for_registry(room_id)

    case Core.RoomRegistry.get_loop(room_key) do
      {:ok, pid} ->
        send(pid, {:move_input, dx, dy})

      :error ->
        Logger.warning(
          "[input:ZenohBridge] forward_move_input FAILED: No event handler for room=#{room_id}, dropping (dx=#{dx}, dy=#{dy})"
        )
    end
  end

  defp forward_ui_action(room_id, name) do
    room_key = room_id_for_registry(room_id)

    case Core.RoomRegistry.get_loop(room_key) do
      {:ok, pid} ->
        send(pid, {:ui_action, name})

      :error ->
        Logger.debug(
          "[ZenohBridge] No event handler for room=#{room_id}, dropping action #{name}"
        )
    end
  end

  # Core.RoomRegistry の登録形式: :main は atom、他ルームは binary のまま
  defp room_id_for_registry("main"), do: :main
  defp room_id_for_registry(id) when is_binary(id), do: id

  # ── client_info ETS ──────────────────────────────────────────────────────

  defp ensure_client_info_table do
    if :ets.whereis(:client_info) == :undefined do
      :ets.new(:client_info, [:named_table, :public, :set, read_concurrency: true])
    end
  end

  # client_info の room_id 最大数（DoS 対策: 無制限の room 作成でメモリ枯渇を防ぐ）
  @client_info_max_rooms 100

  defp handle_client_info(room_id, payload) do
    if valid_room_id_for_client_info?(room_id) do
      room_key = if room_id == "main", do: :main, else: room_id

      if new_client_info_room?(room_key) and client_info_table_at_limit?() do
        Logger.warning(
          "[ZenohBridge] Rejected client_info: max rooms (#{@client_info_max_rooms}) reached"
        )
      else
        do_handle_client_info(room_id, room_key, payload)
      end
    else
      Logger.debug("[ZenohBridge] Rejected client_info: invalid room_id=#{inspect(room_id)}")
    end
  end

  defp do_handle_client_info(room_id, room_key, payload) do
    case decode_client_info(payload) do
      {:ok, info} when is_map(info) ->
        case normalize_client_info(info) do
          normalized when is_map(normalized) ->
            :ets.insert(:client_info, {{room_key, :info}, normalized})

          _ ->
            Logger.debug("[ZenohBridge] Invalid client info structure room=#{room_id}")
        end

      _ ->
        Logger.debug("[ZenohBridge] Invalid client info payload room=#{room_id}")
    end
  end

  defp valid_room_id_for_client_info?(room_id) when is_binary(room_id) do
    byte_size(room_id) in 1..64 and Regex.match?(~r/^[a-zA-Z0-9_-]+$/, room_id)
  end

  defp valid_room_id_for_client_info?(_), do: false

  defp new_client_info_room?(room_key) do
    :ets.whereis(:client_info) != :undefined and
      :ets.lookup(:client_info, {room_key, :info}) == []
  end

  defp client_info_table_at_limit? do
    case :ets.info(:client_info, :size) do
      size when is_integer(size) -> size >= @client_info_max_rooms
      _ -> false
    end
  end

  defp decode_client_info(payload) when is_binary(payload) and byte_size(payload) > 0 do
    case try_decode_client_info_protobuf(payload) do
      {:ok, info} ->
        {:ok, info}

      {:error, _} ->
        :error
    end
  end

  defp decode_client_info(_), do: :error

  defp try_decode_movement_protobuf(payload) when is_binary(payload) do
    case Alchemy.Input.Movement.decode(payload) do
      %Alchemy.Input.Movement{dx: dx, dy: dy} when is_number(dx) and is_number(dy) ->
        {:ok, {dx, dy}}

      _ ->
        {:error, :invalid_protobuf_movement}
    end
  rescue
    e ->
      Logger.debug("[input:ZenohBridge] movement protobuf decode failed: #{Exception.message(e)}")

      {:error, :invalid_protobuf_movement}
  end

  defp try_decode_action_protobuf(payload) when is_binary(payload) do
    case Alchemy.Input.Action.decode(payload) do
      %Alchemy.Input.Action{name: name} when is_binary(name) and byte_size(name) > 0 ->
        {:ok, name}

      _ ->
        {:error, :invalid_protobuf_action}
    end
  rescue
    e ->
      Logger.debug("[input:ZenohBridge] action protobuf decode failed: #{Exception.message(e)}")

      {:error, :invalid_protobuf_action}
  end

  defp try_decode_client_info_protobuf(payload) when is_binary(payload) do
    case Alchemy.Client.ClientInfo.decode(payload) do
      %Alchemy.Client.ClientInfo{os: os, arch: arch, family: family}
      when is_binary(os) and is_binary(arch) and is_binary(family) ->
        {:ok, %{"os" => os, "arch" => arch, "family" => family}}

      _ ->
        {:error, :invalid_protobuf_client_info}
    end
  rescue
    e ->
      Logger.debug("[ZenohBridge] client_info protobuf decode failed: #{Exception.message(e)}")

      {:error, :invalid_protobuf_client_info}
  end

  defp normalize_client_info(%{os: o, arch: a, family: f}) do
    with {:ok, os} <- safe_to_string(o),
         {:ok, arch} <- safe_to_string(a),
         {:ok, family} <- safe_to_string(f) do
      %{os: os, arch: arch, family: family}
    else
      _ -> nil
    end
  end

  defp normalize_client_info(%{"os" => o, "arch" => a, "family" => f}) do
    with {:ok, os} <- safe_to_string(o),
         {:ok, arch} <- safe_to_string(a),
         {:ok, family} <- safe_to_string(f) do
      %{os: os, arch: arch, family: family}
    else
      _ -> nil
    end
  end

  defp normalize_client_info(_), do: nil

  # to_string/1 は map や不正な list 等で ArgumentError を起こすため、
  # 攻撃者が ZenohBridge をクラッシュさせる DoS の原因になる。
  # 安全な型のみ許可する。
  defp safe_to_string(v) when is_binary(v), do: {:ok, v}
  defp safe_to_string(v) when is_atom(v), do: {:ok, Atom.to_string(v)}
  defp safe_to_string(v) when is_integer(v), do: {:ok, Integer.to_string(v)}
  defp safe_to_string(v) when is_float(v), do: {:ok, Float.to_string(v)}

  defp safe_to_string(v) when is_list(v) do
    if List.ascii_printable?(v), do: {:ok, List.to_string(v)}, else: :error
  end

  defp safe_to_string(_), do: :error
end
