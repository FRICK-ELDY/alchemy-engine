defmodule Auth.Repo.Migrations.AddAccountLifecycle do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :email_verified_at, :utc_datetime
    end

    create table(:account_tokens, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token_hash, :text, null: false
      add :purpose, :text, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:account_tokens, [:token_hash],
             name: "account_tokens_unique_token_hash_index"
           )

    create index(:account_tokens, [:user_id, :purpose],
             name: "account_tokens_user_id_purpose_index"
           )
  end

  def down do
    drop table(:account_tokens)

    alter table(:users) do
      remove :email_verified_at
    end
  end
end
