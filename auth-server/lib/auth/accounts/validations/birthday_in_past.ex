defmodule Auth.Accounts.Validations.BirthdayInPast do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :birthday) do
      nil ->
        :ok

      %Date{} = birthday ->
        if Date.compare(birthday, Date.utc_today()) == :gt do
          {:error, InvalidAttribute.exception(field: :birthday, message: "must be in the past")}
        else
          :ok
        end

      _ ->
        :ok
    end
  end
end
