defmodule Auth.Accounts.Validations.PasswordComplexity do
  @moduledoc false

  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    argument = Keyword.get(opts, :argument, :password)
    password = Ash.Changeset.get_argument(changeset, argument)

    cond do
      not is_binary(password) or password == "" ->
        {:error, field: argument, message: "is required"}

      String.length(password) < 8 ->
        {:error, field: argument, message: "must be at least 8 characters"}

      not Regex.match?(~r/[0-9]/, password) ->
        {:error, field: argument, message: "must contain at least 1 digit"}

      not Regex.match?(~r/[a-z]/, password) ->
        {:error, field: argument, message: "must contain at least 1 lowercase letter"}

      not Regex.match?(~r/[A-Z]/, password) ->
        {:error, field: argument, message: "must contain at least 1 uppercase letter"}

      true ->
        :ok
    end
  end
end
