# Debug seed accounts for local development.
#
# Run manually with:
#
#     mix run priv/repo/seeds.exs
#
# Also runs automatically on `docker compose up` (after migrations).
# Idempotent: existing accounts are skipped, so re-running is safe.
# Dev/test convenience only — never wire this into a production release.

if Mix.env() == :prod do
  IO.puts("seeds: skipped (prod environment)")
else
  debug_users = [
    %{username: "alice", email: "alice@example.com"},
    %{username: "bob", email: "bob@example.com"},
    %{username: "carol", email: "carol@example.com"},
    %{username: "admin", email: "admin@example.com"}
  ]

  # Satisfies password complexity: 8+ chars, 1 digit, 1 lowercase, 1 uppercase.
  password = "Password1"

  for attrs <- debug_users do
    case Auth.Accounts.User.get_by_username(attrs.username) do
      {:ok, _user} ->
        IO.puts("seeds: skip (already exists): #{attrs.username}")

      {:error, _not_found} ->
        case Auth.Accounts.register(%{
               username: attrs.username,
               email: attrs.email,
               password: password,
               birthday: ~D[2000-01-01],
               promo_code: nil,
               tos_agreed: true
             }) do
          {:ok, user} ->
            IO.puts("seeds: created #{user.username} <#{user.email}> (password: #{password})")

          {:error, error} ->
            IO.puts("seeds: FAILED for #{attrs.username}: #{Exception.message(error)}")
        end
    end
  end
end
