defmodule Auth.Accounts.RefreshToken do
  @moduledoc """
  Opaque refresh tokens for "Remember Me" sessions.

  Only a SHA-256 hash of the token is stored. Tokens belong to a `family_id`
  chain and rotate on each refresh. Tokens expire after
  `refresh_token_inactivity_days` of inactivity (sliding window on
  `last_used_at`).
  """

  use Ash.Resource,
    otp_app: :auth,
    domain: Auth.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "refresh_tokens"
    repo Auth.Repo

    references do
      reference :user, on_delete: :delete, index?: true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :family_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :token_hash, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :last_used_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :revoked_at, :utc_datetime do
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
      get? true
      argument :token_hash, :string, allow_nil?: false, sensitive?: true
      filter expr(token_hash == ^arg(:token_hash))
    end

    create :create do
      accept [:user_id, :family_id, :token_hash, :last_used_at]
    end

    update :revoke do
      accept [:revoked_at]
    end

    destroy :destroy do
      primary? true
    end
  end

  code_interface do
    define :create, action: :create
    define :get_by_token_hash, action: :get_by_token_hash, args: [:token_hash]
    define :revoke, action: :revoke
  end
end
