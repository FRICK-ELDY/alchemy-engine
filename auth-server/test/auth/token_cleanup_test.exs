defmodule Auth.TokenCleanupTest do
  use Auth.DataCase, async: true

  import Auth.AccountsFixtures

  alias Auth.Accounts
  alias Auth.Accounts.{RefreshToken, TokenRevocation}
  alias Auth.TokenCleanup

  describe "run_now/0" do
    test "deletes expired token revocations" do
      user = user_fixture()
      past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)
      jti = Ecto.UUID.generate()

      assert {:ok, _} =
               TokenRevocation.revoke(%{
                 jti: jti,
                 user_id: user.id,
                 expires_at: past
               })

      assert %{revocations: 1, refresh_tokens: _} = TokenCleanup.run_now()
      assert {:error, _} = TokenRevocation.get_by_jti(jti)
    end

    test "deletes revoked refresh tokens past the grace period" do
      user = user_fixture()
      {:ok, session} = Accounts.issue_session(user, true)
      {:ok, record} = RefreshToken.get_by_token_hash(hash_token(session.refresh_token))

      stale_revoked =
        DateTime.add(DateTime.utc_now(), -8 * 86_400, :second) |> DateTime.truncate(:second)

      {:ok, _} = RefreshToken.revoke(record, %{revoked_at: stale_revoked})

      assert %{refresh_tokens: 1} = TokenCleanup.run_now()
      assert {:error, _} = RefreshToken.get_by_token_hash(hash_token(session.refresh_token))
    end

    test "deletes refresh tokens expired by inactivity past the grace period" do
      user = user_fixture()

      stale_last_used =
        DateTime.add(DateTime.utc_now(), -16 * 86_400, :second) |> DateTime.truncate(:second)

      plaintext = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

      assert {:ok, _} =
               RefreshToken.create(%{
                 user_id: user.id,
                 family_id: Ecto.UUID.generate(),
                 token_hash: hash_token(plaintext),
                 last_used_at: stale_last_used
               })

      assert %{refresh_tokens: 1} = TokenCleanup.run_now()
      assert {:error, _} = RefreshToken.get_by_token_hash(hash_token(plaintext))
    end

    test "keeps active refresh tokens and unexpired revocations" do
      user = user_fixture()
      {:ok, session} = Accounts.issue_session(user, true)

      future = DateTime.add(DateTime.utc_now(), 900, :second) |> DateTime.truncate(:second)

      assert {:ok, _} =
               TokenRevocation.revoke(%{
                 jti: Ecto.UUID.generate(),
                 user_id: user.id,
                 expires_at: future
               })

      assert %{revocations: 0, refresh_tokens: 0} = TokenCleanup.run_now()
      assert {:ok, _} = RefreshToken.get_by_token_hash(hash_token(session.refresh_token))
    end
  end

  defp hash_token(plaintext) do
    :sha256 |> :crypto.hash(plaintext) |> Base.encode16(case: :lower)
  end
end
