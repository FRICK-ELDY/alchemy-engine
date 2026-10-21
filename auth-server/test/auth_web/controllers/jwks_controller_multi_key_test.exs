defmodule AuthWeb.JwksControllerMultiKeyTest do
  use AuthWeb.ConnCase, async: false

  alias Auth.Token.Keys

  @alt_path "test/support/fixtures/jwt_private_alt.pem"

  setup do
    previous_verification = Application.get_env(:auth, :jwt_verification_key_paths)

    on_exit(fn ->
      Application.put_env(:auth, :jwt_verification_key_paths, previous_verification)
      restart_keys!()
    end)

    Application.put_env(:auth, :jwt_verification_key_paths, [@alt_path])
    restart_keys!()

    {:ok, conn: build_conn()}
  end

  test "GET /.well-known/jwks.json returns multiple keys", %{conn: conn} do
    conn = get(conn, ~p"/.well-known/jwks.json")

    assert %{"keys" => keys} = json_response(conn, 200)
    assert length(keys) == 2

    Enum.each(keys, fn key ->
      assert key["kty"] == "RSA"
      assert key["alg"] == "RS256"
      assert key["use"] == "sig"
      assert is_binary(key["kid"])
    end)

    kids = Enum.map(keys, & &1["kid"])
    assert Enum.uniq(kids) == kids
    assert first_jwks_kid() in kids
  end

  defp first_jwks_kid do
    Keys.jwks() |> Map.fetch!("keys") |> List.first() |> Map.fetch!("kid")
  end

  defp restart_keys! do
    _ = Supervisor.terminate_child(Auth.Supervisor, Keys)

    case Supervisor.restart_child(Auth.Supervisor, Keys) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> flunk("failed to restart Auth.Token.Keys: #{inspect(reason)}")
    end

    wait_for_keys!()
  end

  defp wait_for_keys! do
    Enum.reduce_while(1..100, :error, fn _, _ ->
      case Keys.jwks() do
        %{"keys" => [_ | _]} ->
          {:halt, :ok}

        _ ->
          Process.sleep(20)
          {:cont, :error}
      end
    end)
    |> case do
      :ok -> :ok
      :error -> flunk("Auth.Token.Keys did not become ready")
    end
  catch
    :exit, {:noproc, _} ->
      Process.sleep(50)
      wait_for_keys!()
  end
end
