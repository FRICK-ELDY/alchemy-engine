defmodule Auth.Accounts.Changes.StampTosAgreement do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.change_attribute(
      :tos_agreed_at,
      DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Ash.Changeset.change_attribute(
      :tos_version,
      Application.fetch_env!(:auth, :tos_version)
    )
  end
end
