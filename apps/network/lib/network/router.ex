defmodule Network.Router do
  @moduledoc """
  HTTP ルーター。

  - `POST /api/room_token` — ルーム参加用トークン発行（`AUTH_REQUIRED` 時は Bearer JWT 必須）
  - `GET /health` — ヘルスチェック
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/api/room_token" do
    case authorize_room_token(conn) do
      :ok ->
        issue_room_token(conn)

      {:error, reason} ->
        body =
          Phoenix.json_library().encode!(%{
            error: "unauthorized",
            message: unauthorized_message(reason)
          })

        send_json(conn, 401, body)
    end
  end

  get "/health" do
    {status_code, body} =
      case fetch_rooms() do
        {:ok, rooms} ->
          body =
            Phoenix.json_library().encode!(%{
              status: "ok",
              rooms: length(rooms),
              room_ids: Enum.map(rooms, &to_string/1)
            })

          {200, body}

        {:error, reason} ->
          body =
            Phoenix.json_library().encode!(%{
              status: "degraded",
              reason: inspect(reason)
            })

          {503, body}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, body)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp issue_room_token(conn) do
    case conn.body_params do
      %{"room_id" => room_id} when is_binary(room_id) and room_id != "" ->
        {:ok, token} = Network.RoomToken.sign(room_id)
        body = Phoenix.json_library().encode!(%{token: token})
        send_json(conn, 200, body)

      _ ->
        body =
          Phoenix.json_library().encode!(%{
            error: "missing_room_id",
            message: "room_id is required and must be a non-empty string"
          })

        send_json(conn, 400, body)
    end
  end

  defp authorize_room_token(conn) do
    if Application.get_env(:network, :auth_required, false) do
      case bearer_token(conn) do
        {:ok, token} ->
          case Network.AuthVerifier.verify(token) do
            {:ok, _claims} -> :ok
            {:error, reason} -> {:error, reason}
          end

        :error ->
          {:error, :missing_bearer}
      end
    else
      :ok
    end
  end

  defp bearer_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        token = String.trim(token)
        if token == "", do: :error, else: {:ok, token}

      _ ->
        :error
    end
  end

  defp unauthorized_message(:missing_bearer), do: "Bearer token is required"
  defp unauthorized_message(:missing_kid), do: "JWT kid is required"
  defp unauthorized_message(:invalid_alg), do: "JWT alg must be RS256"
  defp unauthorized_message(:unknown_kid), do: "JWT kid is unknown"
  defp unauthorized_message(:inactive_status), do: "user status is not active"
  defp unauthorized_message({:jwks_unavailable, _}), do: "JWKS unavailable"
  defp unauthorized_message({:token_validation_failed, _}), do: "JWT validation failed"
  defp unauthorized_message(_), do: "unauthorized"

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  # Network.Local がダウンしている場合（プロセス不在・タイムアウト・TOCTOU）は
  # {:error, reason} を返す。:exit は GenServer.call が失敗する全ケースをカバーする。
  defp fetch_rooms do
    {:ok, Network.Local.list_rooms()}
  catch
    :exit, reason -> {:error, reason}
  end
end
