defmodule Auth.AshErrors do
  @moduledoc false

  @spec not_found?(term()) :: boolean()
  def not_found?(%Ash.Error.Query.NotFound{}), do: true

  def not_found?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &not_found?/1)
  end

  def not_found?(_), do: false
end
