defmodule Network.RoomToken do
  @moduledoc """
  ルーム参加用トークンの生成・検証。

  `Phoenix.Token` を使ってルームIDをスコープとした署名付きトークンを発行し、
  WebSocket チャンネル join 時の認証に使用する。

  ## トークンのペイロード

  - `room_id`（String）— 参加を許可するルームID

  ## 有効期限

  - デフォルト: 5分（300秒）
  - `max_age` オプションで変更可能
  """

  @salt "room join"
  @max_age 300

  @doc """
  ルーム参加用トークンを生成する。

  ## 例

      iex> Network.RoomToken.sign("my_room")
      {:ok, "SFMyNTY.g2gD..."}

      iex> Network.RoomToken.sign("room_a", max_age: 600)
      {:ok, "SFMyNTY.g2gD..."}
  """
  @spec sign(String.t(), keyword()) :: {:ok, String.t()}
  def sign(room_id, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, @max_age)
    token = Phoenix.Token.sign(Network.Endpoint, @salt, room_id, max_age: max_age)
    {:ok, token}
  end

  @doc """
  トークンを検証し、ペイロード（room_id）を返す。

  検証に成功した場合、返却された room_id が引数 `room_id` と一致するかを
  呼び出し側で確認すること（スコープ制限）。

  ## 例

      iex> {:ok, token} = Network.RoomToken.sign("my_room")
      iex> Network.RoomToken.verify(token, "my_room")
      :ok

      iex> Network.RoomToken.verify(token, "other_room")
      {:error, :scope_mismatch}

      iex> Network.RoomToken.verify("invalid", "my_room")
      {:error, :invalid}

      iex> Network.RoomToken.verify(nil, "my_room")
      {:error, :missing}
  """
  @spec verify(String.t() | nil, String.t()) ::
          :ok | {:error, :expired | :invalid | :missing | :scope_mismatch}
  def verify(nil, _room_id), do: {:error, :missing}
  def verify("", _room_id), do: {:error, :missing}

  def verify(token, room_id) when is_binary(token) do
    case Phoenix.Token.verify(Network.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, ^room_id} ->
        :ok

      {:ok, _other_room_id} ->
        {:error, :scope_mismatch}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
