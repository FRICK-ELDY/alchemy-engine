defmodule AuthWeb.ClientIp do
  @moduledoc false

  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(conn) do
    peer = conn.remote_ip
    proxies = Application.get_env(:auth, :trusted_proxies, [])

    cond do
      proxies == [] ->
        format(peer)

      trusted_proxy?(peer, proxies) ->
        conn.req_headers
        |> RemoteIp.from(headers: ~w[x-forwarded-for], proxies: proxies)
        |> case do
          nil -> format(peer)
          ip -> format(ip)
        end

      true ->
        format(peer)
    end
  end

  defp trusted_proxy?(peer, proxies) do
    Enum.any?(proxies, &proxy_match?(&1, peer))
  end

  defp proxy_match?(proxy, peer) do
    case RemoteIp.Block.parse(proxy) do
      {:ok, block} -> RemoteIp.Block.contains?(block, RemoteIp.Block.encode(peer))
      _ -> format(peer) == proxy
    end
  end

  defp format(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
  end
end
