defmodule Network.Router do
  @moduledoc """
  HTTP ルーター。

  WebSocket 以外の HTTP リクエストを処理する。
  現在は `/health` エンドポイントのみ提供する。
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/api/room_token" do
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
