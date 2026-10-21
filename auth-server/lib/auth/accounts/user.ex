defmodule Auth.Accounts.User do
  @moduledoc """
  User identity resource. SSoT for alchemy-platform user accounts.
  """

  use Ash.Resource,
    otp_app: :auth,
    domain: Auth.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo Auth.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :username, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :password_hash, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :status, :atom do
      constraints one_of: [:active, :suspended, :deleted]
      default :active
      allow_nil? false
      public? true
    end

    attribute :birthday, :date do
      allow_nil? false
      public? true
    end

    attribute :promo_code, :string do
      public? true
    end

    attribute :tos_agreed_at, :utc_datetime do
      allow_nil? false
    end

    attribute :tos_version, :string do
      allow_nil? false
    end

    attribute :email_verified_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_email, [:email]
    identity :unique_username, [:username]
  end

  actions do
    defaults [:read]

    read :get_by_email do
      get? true
      argument :email, :ci_string, allow_nil?: false
      filter expr(email == ^arg(:email))
    end

    read :get_by_username do
      get? true
      argument :username, :ci_string, allow_nil?: false
      filter expr(username == ^arg(:username))
    end

    create :register do
      accept [:username, :email, :birthday, :promo_code]
      argument :password, :string, allow_nil?: false, sensitive?: true
      argument :tos_agreed, :boolean, allow_nil?: false

      validate match(:username, ~r/^[a-zA-Z0-9_]{3,20}$/) do
        message "must be 3-20 characters using only letters, digits, and underscores"
      end

      validate match(:email, ~r/^[^\s@]+@[^\s@]+$/) do
        message "must be a valid email address"
      end

      validate present(:password) do
        message "is required"
      end

      validate string_length(:password, min: 8) do
        message "must be at least 8 characters"
      end

      validate match(:password, ~r/[0-9]/) do
        message "must contain at least 1 digit"
      end

      validate match(:password, ~r/[a-z]/) do
        message "must contain at least 1 lowercase letter"
      end

      validate match(:password, ~r/[A-Z]/) do
        message "must contain at least 1 uppercase letter"
      end

      validate argument_equals(:tos_agreed, true) do
        message "must be accepted"
      end

      validate Auth.Accounts.Validations.BirthdayInPast

      change Auth.Accounts.Changes.HashPassword
      change Auth.Accounts.Changes.StampTosAgreement
    end

    update :set_status do
      accept [:status]
    end

    update :verify_email do
      require_atomic? false

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(
          changeset,
          :email_verified_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )
      end
    end

    update :change_password do
      require_atomic? false
      argument :password, :string, allow_nil?: false, sensitive?: true

      validate {Auth.Accounts.Validations.PasswordComplexity, argument: :password}
      change {Auth.Accounts.Changes.SetPasswordHash, argument: :password}
    end

    update :deactivate do
      change set_attribute(:status, :deleted)
    end
  end

  code_interface do
    define :register, action: :register
    define :get_by_email, action: :get_by_email, args: [:email]
    define :get_by_username, action: :get_by_username, args: [:username]
    define :set_status, action: :set_status
    define :verify_email, action: :verify_email
    define :change_password, action: :change_password
    define :deactivate, action: :deactivate
  end
end
