defmodule Auth.Token.KeysTest do
  use ExUnit.Case, async: false

  import Auth.AccountsFixtures

  alias Auth.Token
  alias Auth.Token.Keys

  @primary_path "test/support/fixtures/jwt_private.pem"
  @alt_path "test/support/fixtures/jwt_private_alt.pem"

  setup do
    previous_primary = Application.get_env(:auth, :jwt_private_key_path)
    previous_verification = Application.get_env(:auth, :jwt_verification_key_paths)

    on_exit(fn ->
      Application.put_env(:auth, :jwt_private_key_path, previous_primary)
      Application.put_env(:auth, :jwt_verification_key_paths, previous_verification)
      restart_keys!()
    end)

    Application.put_env(:auth, :jwt_private_key_path, @primary_path)
    Application.put_env(:auth, :jwt_verification_key_paths, [])
    restart_keys!()

    :ok
  end

  test "active signer kid matches JWKS first key" do
    assert active_kid() == first_jwks_kid()
  end

  test "signer_for_kid returns active signer" do
    kid = active_kid()
    assert {:ok, signer} = Keys.signer_for_kid(kid)
    assert signer == Keys.signer()
  end

  test "signer_for_kid returns error for unknown kid" do
    assert {:error, :unknown_kid} = Keys.signer_for_kid("unknown-kid")
  end

  test "jwks includes verification keys" do
    Application.put_env(:auth, :jwt_verification_key_paths, [@alt_path])
    restart_keys!()

    kids = Keys.jwks() |> Map.fetch!("keys") |> Enum.map(& &1["kid"])
    assert length(kids) == 2
    assert Enum.uniq(kids) == kids
  end

  test "rejects duplicate kid across key paths" do
    Application.put_env(:auth, :jwt_verification_key_paths, [@primary_path])

    _ = Supervisor.terminate_child(Auth.Supervisor, Keys)
    assert {:ok, pid} = Supervisor.restart_child(Auth.Supervisor, Keys)

    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, _, {%ArgumentError{message: message}, _}}, 5_000
    assert message =~ "duplicate JWT key ids"

    Application.put_env(:auth, :jwt_verification_key_paths, [])
    restart_keys!()
  end

  test "verifies token signed with previous key after rotation" do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Auth.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    user = user_fixture(%{email: "rotation@example.com"})
    assert {:ok, old_token, _jti, _} = Token.generate(user)

    Application.put_env(:auth, :jwt_private_key_path, @alt_path)
    Application.put_env(:auth, :jwt_verification_key_paths, [@primary_path])
    restart_keys!()

    assert {:ok, _claims, verified_user} = Token.verify(old_token)
    assert verified_user.id == user.id

    assert {:ok, new_token, _jti, _} = Token.generate(user)
    assert peek_token_kid(new_token) == active_kid()
    refute peek_token_kid(new_token) == peek_token_kid(old_token)
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

  defp active_kid, do: first_jwks_kid()

  defp first_jwks_kid do
    Keys.jwks() |> Map.fetch!("keys") |> List.first() |> Map.fetch!("kid")
  end

  defp peek_token_kid(token) do
    [header_b64 | _] = String.split(token, ".")
    header_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!() |> Map.fetch!("kid")
  end
end
