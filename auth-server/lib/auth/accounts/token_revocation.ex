defmodule Auth.Accounts.TokenRevocation do
  @moduledoc """
  Records revoked JWT `jti` values for logout.
  """

  use Ash.Resource,
    otp_app: :auth,
    domain: Auth.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "token_revocations"
    repo Auth.Repo
  end

  attributes do
    attribute :jti, :uuid do
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    create_timestamp :revoked_at
  end

  actions do
    defaults [:read]

    read :get_by_jti do
      get? true
      argument :jti, :uuid, allow_nil?: false
      filter expr(jti == ^arg(:jti))
    end

    create :revoke do
      accept [:jti, :user_id, :expires_at]
    end

    destroy :destroy do
      primary? true
    end
  end

  code_interface do
    define :revoke, action: :revoke
    define :get_by_jti, action: :get_by_jti, args: [:jti]
  end
end
