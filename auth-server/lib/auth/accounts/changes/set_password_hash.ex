defmodule Auth.Accounts.Changes.SetPasswordHash do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    argument = Keyword.get(opts, :argument, :password)
    password = Ash.Changeset.get_argument(changeset, argument)

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
