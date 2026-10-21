defmodule Auth.AccountsFixtures do
  @moduledoc """
  Test helpers for creating `Auth.Accounts` entities.
  """

  @default_password "Password1"

  def default_password, do: @default_password

  def valid_register_attrs(overrides \\ %{}) do
    unique = System.unique_integer([:positive])

    Map.merge(
      %{
        username: "user#{unique}",
        email: "user#{unique}@example.com",
        password: @default_password,
        birthday: ~D[2000-01-31],
        promo_code: nil,
        tos_agreed: true
      },
      overrides
    )
  end

  def user_fixture(overrides \\ %{}) do
    {:ok, user} = Auth.Accounts.register(valid_register_attrs(overrides))
    user
  end

  def user_fixture_without_verification_email(overrides \\ %{}) do
    {:ok, user} = Auth.Accounts.User.register(valid_register_attrs(overrides))
    user
  end

  def verified_user_fixture(overrides \\ %{}) do
    user = user_fixture(overrides)

    {:ok, user} =
      user
      |> Ash.Changeset.for_update(:verify_email, %{})
      |> Ash.update()

    user
  end

  def account_token_fixture(user, purpose, opts \\ []) do
    {:ok, token} = Auth.Accounts.create_account_token_for_test(user, purpose, opts)
    token
  end
end
