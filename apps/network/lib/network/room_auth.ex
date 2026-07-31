defmodule Network.RoomAuth do
  @moduledoc """
  UDP / Zenoh 経路向けの RoomToken 検証。

  `config :network, :auth_required`（環境変数 `AUTH_REQUIRED`）が true のときのみ
  `Network.RoomToken` を必須とする。オフ時はデモ・ローカル向けに無検証（現行互換）。

  WebSocket（`Network.Channel`）は従来どおり常に RoomToken 必須。
  """

  @doc """
  RoomToken 検証が必須かどうか。
  """
  @spec required?() :: boolean()
  def required? do
    Application.get_env(:network, :auth_required, false) == true
  end

  @doc """
  `room_id` 向け RoomToken を検証する。

  `required?()` が false のときは常に `:ok`（token は無視）。
  """
  @spec verify_join_token(String.t() | nil, String.t()) ::
          :ok | {:error, :missing | :expired | :invalid | :scope_mismatch}
  def verify_join_token(token, room_id) when is_binary(room_id) do
    if required?() do
      Network.RoomToken.verify(token, room_id)
    else
      :ok
    end
  end

  @doc """
  AUTH_REQUIRED 時の Zenoh ペイロード封筒を解く。

  形式: `<<token_len::16-big, token::binary-size(token_len), protobuf::binary>>`

  オフ時は payload をそのまま返す（既存クライアント互換）。
  """
  @spec unwrap_payload(binary(), String.t()) ::
          {:ok, binary()}
          | {:error, :missing | :expired | :invalid | :scope_mismatch | :missing_token}
  def unwrap_payload(payload, room_id) when is_binary(payload) and is_binary(room_id) do
    if required?() do
      case payload do
        <<len::16-big, token::binary-size(len), rest::binary>> when len > 0 ->
          case Network.RoomToken.verify(token, room_id) do
            :ok -> {:ok, rest}
            {:error, _} = err -> err
          end

        _ ->
          {:error, :missing_token}
      end
    else
      {:ok, payload}
    end
  end

  @doc """
  RoomToken 付き Zenoh ペイロードを組み立てる（テスト・クライアント向け）。
  """
  @spec wrap_payload(String.t(), binary()) :: binary()
  def wrap_payload(token, protobuf)
      when is_binary(token) and token != "" and is_binary(protobuf) do
    <<byte_size(token)::16-big, token::binary, protobuf::binary>>
  end
end
