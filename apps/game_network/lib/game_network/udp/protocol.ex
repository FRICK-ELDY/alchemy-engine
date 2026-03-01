defmodule GameNetwork.UDP.Protocol do
  @moduledoc """
  UDP パケットのエンコード・デコードとデルタ圧縮。

  ## パケット形式

  全パケットは以下の固定ヘッダを持つ:

      <<type::8, seq::32, payload::binary>>

  | フィールド | サイズ | 説明 |
  |:-----------|:-------|:-----|
  | `type`     | 1 byte | パケット種別（下記参照） |
  | `seq`      | 4 byte | シーケンス番号（big-endian unsigned 32bit） |
  | `payload`  | 可変   | 種別ごとのペイロード |

  ## パケット種別

  | 値 | 名前 | 方向 | 説明 |
  |:---|:-----|:-----|:-----|
  | `0x01` | `:join`        | C→S | ルーム参加要求 |
  | `0x02` | `:join_ack`    | S→C | 参加承認 |
  | `0x03` | `:leave`       | C→S | ルーム離脱 |
  | `0x04` | `:input`       | C→S | 移動入力 |
  | `0x05` | `:action`      | C→S | UI アクション |
  | `0x06` | `:frame`       | S→C | フレームイベント（デルタ圧縮） |
  | `0x07` | `:ping`        | C→S | 疎通確認 |
  | `0x08` | `:pong`        | S→C | 疎通応答 |
  | `0x09` | `:error`       | S→C | エラー通知 |

  ## デルタ圧縮

  `:frame` パケットのペイロードは zlib で圧縮した Erlang term バイナリ。
  クライアントは直前のフレームとの差分のみを受け取ることで帯域を節約する。
  現フェーズでは全フレームデータを送信し、差分計算はフェーズ4以降で実装する。
  """

  @type_join 0x01
  @type_join_ack 0x02
  @type_leave 0x03
  @type_input 0x04
  @type_action 0x05
  @type_frame 0x06
  @type_ping 0x07
  @type_pong 0x08
  @type_error 0x09

  @type packet ::
          {:join, seq :: non_neg_integer(), room_id :: String.t()}
          | {:join_ack, seq :: non_neg_integer(), room_id :: String.t()}
          | {:leave, seq :: non_neg_integer(), room_id :: String.t()}
          | {:input, seq :: non_neg_integer(), dx :: float(), dy :: float()}
          | {:action, seq :: non_neg_integer(), name :: String.t()}
          | {:frame, seq :: non_neg_integer(), events :: list()}
          | {:ping, seq :: non_neg_integer()}
          | {:pong, seq :: non_neg_integer(), ts :: integer()}
          | {:error, seq :: non_neg_integer(), reason :: String.t()}

  @doc """
  パケットをバイナリにエンコードする。

  `:frame` パケットの圧縮に失敗した場合は `{:error, term()}` を返す。
  それ以外のパケット種別は常に `{:ok, binary()}` を返す。
  """
  @spec encode(packet()) :: {:ok, binary()} | {:error, term()}
  def encode({:join, seq, room_id}) do
    room_bin = to_string(room_id)
    {:ok, <<@type_join, seq::32, room_bin::binary>>}
  end

  def encode({:join_ack, seq, room_id}) do
    room_bin = to_string(room_id)
    {:ok, <<@type_join_ack, seq::32, room_bin::binary>>}
  end

  def encode({:leave, seq, room_id}) do
    room_bin = to_string(room_id)
    {:ok, <<@type_leave, seq::32, room_bin::binary>>}
  end

  def encode({:input, seq, dx, dy}) do
    {:ok, <<@type_input, seq::32, dx::float-64, dy::float-64>>}
  end

  def encode({:action, seq, name}) do
    {:ok, <<@type_action, seq::32, name::binary>>}
  end

  def encode({:frame, seq, events}) do
    case compress_events(events) do
      {:ok, compressed} -> {:ok, <<@type_frame, seq::32, compressed::binary>>}
      {:error, _} = err -> err
    end
  end

  def encode({:ping, seq}) do
    {:ok, <<@type_ping, seq::32>>}
  end

  def encode({:pong, seq, ts}) do
    {:ok, <<@type_pong, seq::32, ts::64>>}
  end

  def encode({:error, seq, reason}) do
    {:ok, <<@type_error, seq::32, reason::binary>>}
  end

  @doc """
  バイナリをパケットにデコードする。
  不正なパケットは `{:error, :invalid_packet}` を返す。
  """
  @spec decode(binary()) :: {:ok, packet()} | {:error, :invalid_packet}
  def decode(<<@type_join, seq::32, room_id::binary>>) do
    {:ok, {:join, seq, room_id}}
  end

  def decode(<<@type_join_ack, seq::32, room_id::binary>>) do
    {:ok, {:join_ack, seq, room_id}}
  end

  def decode(<<@type_leave, seq::32, room_id::binary>>) do
    {:ok, {:leave, seq, room_id}}
  end

  def decode(<<@type_input, seq::32, dx::float-64, dy::float-64>>) do
    {:ok, {:input, seq, dx, dy}}
  end

  def decode(<<@type_action, seq::32, name::binary>>) do
    {:ok, {:action, seq, name}}
  end

  def decode(<<@type_frame, seq::32, compressed::binary>>) do
    case decompress_events(compressed) do
      {:ok, events} -> {:ok, {:frame, seq, events}}
      :error -> {:error, :invalid_packet}
    end
  end

  def decode(<<@type_ping, seq::32>>) do
    {:ok, {:ping, seq}}
  end

  def decode(<<@type_pong, seq::32, ts::64>>) do
    {:ok, {:pong, seq, ts}}
  end

  def decode(<<@type_error, seq::32, reason::binary>>) do
    {:ok, {:error, seq, reason}}
  end

  def decode(_), do: {:error, :invalid_packet}

  # ── デルタ圧縮 ──────────────────────────────────────────────────────

  @doc """
  イベントリストを zlib で圧縮した binary に変換する。

  現フェーズでは全イベントを送信する（差分計算なし）。
  Erlang term_to_binary + zlib deflate の組み合わせで
  繰り返しパターンの多いゲームイベントを効率的に圧縮する。

  圧縮に失敗した場合は `{:error, reason}` を返す。
  """
  @spec compress_events(list()) :: {:ok, binary()} | {:error, term()}
  def compress_events(events) do
    {:ok, events |> :erlang.term_to_binary() |> :zlib.compress()}
  rescue
    e -> {:error, e}
  end

  @doc """
  `compress_events/1` で圧縮したバイナリを復元する。
  """
  @spec decompress_events(binary()) :: {:ok, list()} | :error
  def decompress_events(compressed) do
    decompressed = :zlib.uncompress(compressed)
    {:ok, :erlang.binary_to_term(decompressed, [:safe])}
  rescue
    _ -> :error
  end
end
