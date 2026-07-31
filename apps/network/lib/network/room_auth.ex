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
  Zenoh ペイロード封筒を解く。

  形式: `<<token_len::16-big, token::binary-size(token_len), protobuf::binary>>`

  `AUTH_REQUIRED` オフ時も、ラップ済みペイロードを検出できれば protobuf 部分だけを返す
  （新クライアントが常にラップしても旧サーバ設定で壊れない）。
  必須オン時はトークン検証失敗をエラーにする。
  """
  @spec unwrap_payload(binary(), String.t()) ::
          {:ok, binary()}
          | {:error, :missing | :expired | :invalid | :scope_mismatch | :missing_token}
  def unwrap_payload(payload, room_id) when is_binary(payload) and is_binary(room_id) do
    case payload do
      <<len::16-big, token::binary-size(len), rest::binary>> when len > 0 ->
        case Network.RoomToken.verify(token, room_id) do
          :ok ->
            {:ok, rest}

          {:error, reason} ->
            if required?() do
              {:error, reason}
            else
              # オフ時: 封筒らしいペイロードなら rest を採用し、そうでなければ生 protobuf とみなす
              if (reason in [:expired, :scope_mismatch] or len > 30) and looks_like_token?(token) do
                {:ok, rest}
              else
                {:ok, payload}
              end
            end
        end

      _ ->
        if required?() do
          {:error, :missing_token}
        else
          {:ok, payload}
        end
    end
  end

  @doc """
  RoomToken 付き Zenoh ペイロードを組み立てる（テスト・クライアント向け）。

  token 長は 16bit 上限（65535）以内であること。
  """
  @spec wrap_payload(String.t(), binary()) :: binary()
  def wrap_payload(token, protobuf)
      when is_binary(token) and token != "" and byte_size(token) <= 65_535 and
             is_binary(protobuf) do
    <<byte_size(token)::16-big, token::binary, protobuf::binary>>
  end

  # Phoenix.Token は Base64URL + `.` 区切り。生 protobuf の誤検出を避ける。
  defp looks_like_token?(token) when is_binary(token) do
    Regex.match?(~r/^[a-zA-Z0-9._-]+$/, token)
  end
end
