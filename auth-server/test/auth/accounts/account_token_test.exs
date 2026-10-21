defmodule Auth.AccountTokenTest do
  use Auth.DataCase, async: true

  import Auth.AccountsFixtures

  alias Auth.Accounts
  alias Auth.Accounts.AccountToken

  test "stores and fetches account tokens by hash and purpose" do
    user = user_fixture_without_verification_email()
    token = account_token_fixture(user, :email_verification)

    hash =
      :sha256
      |> :crypto.hash(token)
      |> Base.encode16(case: :lower)

    assert {:ok, record} =
             AccountToken
             |> Ash.Query.for_read(:get_by_token_hash, %{
               token_hash: hash,
               purpose: :email_verification
             })
             |> Ash.read_one()

    assert record.user_id == user.id
    assert is_nil(record.used_at)
  end

  test "verify_email accepts tokens created for tests" do
    user = user_fixture_without_verification_email()
    token = account_token_fixture(user, :email_verification)

    assert :ok = Accounts.verify_email(token)
  end
end
