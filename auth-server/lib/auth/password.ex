defmodule Auth.Password do
  @moduledoc """
  Password hashing for user credentials (Argon2id).
  """

  @doc """
  Returns a password hash suitable for storage in `users.password_hash`.
  """
  @spec hash(String.t()) :: String.t()
  def hash(password) when is_binary(password) do
    Argon2.hash_pwd_salt(password)
  end

  @doc """
  Verifies a plaintext password against a stored hash.
  """
  @spec verify(String.t(), String.t() | nil) :: boolean()
  def verify(password, hash) when is_binary(password) and is_binary(hash) do
    Argon2.verify_pass(password, hash)
  rescue
    _ -> false
  end

  def verify(_password, _hash) do
    Argon2.no_user_verify()
    false
  end

  @doc """
  Performs a dummy password verification to mitigate timing attacks on login.
  """
  @spec no_user_verify() :: :ok
  def no_user_verify do
    Argon2.no_user_verify()
    :ok
  end
end
