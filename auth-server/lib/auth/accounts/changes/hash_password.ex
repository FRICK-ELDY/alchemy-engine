defmodule Auth.Accounts.Changes.HashPassword do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    password = Ash.Changeset.get_argument(changeset, :password)

    if is_binary(password) and password != "" do
      Ash.Changeset.change_attribute(
        changeset,
        :password_hash,
        Auth.Password.hash(password)
      )
    else
      changeset
    end
  end
end
