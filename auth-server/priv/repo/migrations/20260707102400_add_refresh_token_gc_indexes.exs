defmodule Auth.Repo.Migrations.AddRefreshTokenGcIndexes do
  use Ecto.Migration

  def up do
    create index(:refresh_tokens, [:revoked_at])
    create index(:refresh_tokens, [:last_used_at])
  end

  def down do
    drop_if_exists index(:refresh_tokens, [:last_used_at])
    drop_if_exists index(:refresh_tokens, [:revoked_at])
  end
end
