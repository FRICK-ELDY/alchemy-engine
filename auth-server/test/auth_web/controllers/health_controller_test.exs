defmodule AuthWeb.HealthControllerTest do
  use AuthWeb.ConnCase, async: true

  test "GET /health", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert %{
             "status" => "ok",
             "service" => "alchemy-auth",
             "version" => version
           } = json_response(conn, 200)

    assert is_binary(version)
  end
end
