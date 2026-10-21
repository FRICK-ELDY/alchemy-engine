defmodule Auth.Accounts.AccountToken do
  @moduledoc """
  One-time tokens for email verification and password reset.

  Only a SHA-256 hash of the plaintext token is stored.
  """

  use Ash.Resource,
    otp_app: :auth,
    domain: Auth.Domain,
    data_layer: AshPostgres.DataLayer

  @purposes [:email_verification, :password_reset]

  postgres do
    table "account_tokens"
    repo Auth.Repo

    references do
      reference :user, on_delete: :delete, index?: false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :token_hash, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :purpose, :atom do
      allow_nil? false
      constraints one_of: @purposes
      public? true
    end

    attribute :expires_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :used_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :user, Auth.Accounts.User do
      allow_nil? false
      public? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_token_hash, [:token_hash]
  end

  actions do
    defaults [:read]

    read :get_by_token_hash do
      argument :token_hash, :string, allow_nil?: false, sensitive?: true
      argument :purpose, :atom, allow_nil?: false
      filter expr(token_hash == ^arg(:token_hash) and purpose == ^arg(:purpose))
    end

    create :create do
      accept [:user_id, :token_hash, :purpose, :expires_at]
    end

    update :consume do
      accept [:used_at]
    end
  end

  code_interface do
    define :create, action: :create
    define :get_by_token_hash, action: :get_by_token_hash, args: [:token_hash, :purpose]
    define :consume, action: :consume
  end
end
