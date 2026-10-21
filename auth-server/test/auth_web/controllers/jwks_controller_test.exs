defmodule AuthWeb.JwksControllerTest do
  use AuthWeb.ConnCase, async: true

  test "GET /.well-known/jwks.json", %{conn: conn} do
    conn = get(conn, ~p"/.well-known/jwks.json")

    assert %{"keys" => [key | _]} = json_response(conn, 200)
    assert key["kty"] == "RSA"
    assert key["alg"] == "RS256"
    assert key["use"] == "sig"
    assert is_binary(key["kid"])
  end
end
