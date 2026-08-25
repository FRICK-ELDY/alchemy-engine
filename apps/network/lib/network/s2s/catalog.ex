defmodule Network.S2S.Catalog do
  @moduledoc """
  連合向けコンテンツメタデータ一覧（ゲーム状態とは分離）。

  設定 `config :network, Network.S2S, worlds: [...]` を読み、
  受信側ポリシー（`max_content_status`）でフィルタする。
  """

  @status_rank %{
    "General" => 0,
    "Sensitive" => 1,
    "Restricted" => 2,
    "Explicit" => 3
  }

  @doc """
  公開可能なワールドメタデータ一覧を返す。

  各要素は string キーのマップ（JSON 直列化向け）。
  """
  @spec list_worlds(keyword()) :: [map()]
  def list_worlds(opts \\ []) do
    cfg = Keyword.merge(Network.S2S.Instance.runtime_config(), opts)
    canonical = Keyword.get(cfg, :canonical_url) || ""
    max_status = Keyword.get(cfg, :max_content_status) || "General"
    worlds = Keyword.get(cfg, :worlds) || []

    worlds
    |> Enum.map(&normalize_world(&1, canonical))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&allowed_status?(&1["status"], max_status))
  end

  @doc false
  @spec status_rank(String.t() | atom()) :: non_neg_integer() | nil
  def status_rank(status), do: Map.get(@status_rank, to_string(status))

  defp normalize_world(world, canonical) when is_map(world) do
    id = world_field(world, :id, "id", "")
    title = world_field(world, :title, "title", id)
    status = world_field(world, :status, "status", "General")
    path = world_field(world, :path, "path", "/worlds/#{id}")
    thumb = world_field(world, :thumbnail_url, "thumbnail_url", nil)
    uri = world_field(world, :uri, "uri", join_uri(canonical, path))

    %{
      "id" => to_string(id),
      "title" => to_string(title),
      "status" => to_string(status),
      "uri" => uri,
      "thumbnail_url" => thumb
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp normalize_world(_, _), do: nil

  defp world_field(world, atom_key, string_key, default) do
    world_get(world, atom_key) || world_get(world, string_key) || default
  end

  defp world_get(map, key) when is_map(map), do: Map.get(map, key)

  defp join_uri("", path), do: path

  defp join_uri(base, path) do
    base = String.trim_trailing(base, "/")
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
    base <> path
  end

  defp allowed_status?(status, max_status) do
    case {status_rank(status), status_rank(max_status)} do
      {nil, _} -> false
      {_, nil} -> false
      {rank, max} -> rank <= max
    end
  end
end
