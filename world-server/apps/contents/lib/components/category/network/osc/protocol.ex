defmodule Contents.Components.Category.Network.Osc.Protocol do
  @moduledoc """
  OSC 1.0 のメッセージ／バンドルを UDP ペイロードとしてエンコード・デコードする。

  Resonite の OSC 実装と同様に、転送は UDP を前提とする。
  対応する引数型: `i` (int32), `f` (float32), `s` (string), `b` (blob), `T`/`F` (bool), `N` (nil)。
  """

  @immediate_timetag <<0, 0, 0, 0, 0, 0, 0, 1>>
  @max_args 256

  @type osc_arg :: integer() | float() | binary() | boolean() | nil
  @type message :: {:message, path :: String.t(), args :: [osc_arg()]}
  @type bundle :: {:bundle, timetag :: :immediate | binary(), elements :: [message() | bundle()]}
  @type packet :: message() | bundle()

  @doc """
  OSC メッセージをバイナリにエンコードする。

  1 パスあたりの引数は 256 個までに制限する（Resonite OSC Sender の上限に合わせる）。
  """
  @spec encode_message(String.t(), [osc_arg()]) :: binary()
  def encode_message(path, args) when is_binary(path) and is_list(args) do
    args = Enum.take(args, @max_args)
    tags = "," <> Enum.map_join(args, &type_tag/1)

    IO.iodata_to_binary([
      encode_string(path),
      encode_string(tags) | Enum.map(args, &encode_arg/1)
    ])
  end

  @doc """
  OSC バンドルをバイナリにエンコードする。

  `elements` は `{path, args}` または既にエンコード済みのバイナリ。
  `timetag` 省略時は immediate（即時実行）。
  """
  @spec encode_bundle([{String.t(), [osc_arg()]} | binary()], :immediate | binary()) :: binary()
  def encode_bundle(elements, timetag \\ :immediate) when is_list(elements) do
    encoded =
      Enum.map(elements, fn
        {path, args} when is_binary(path) and is_list(args) -> encode_message(path, args)
        bin when is_binary(bin) -> bin
      end)

    body =
      Enum.map(encoded, fn bin ->
        <<byte_size(bin)::signed-32-big, bin::binary>>
      end)

    IO.iodata_to_binary([encode_string("#bundle"), encode_timetag(timetag) | body])
  end

  @doc """
  UDP ペイロードを OSC メッセージまたはバンドルとしてデコードする。
  """
  @spec decode(binary()) :: {:ok, packet()} | {:error, :invalid}
  def decode(<<"#bundle", 0, rest::binary>>), do: decode_bundle(rest)
  def decode(bin) when is_binary(bin), do: decode_message(bin)

  defp encode_timetag(:immediate), do: @immediate_timetag
  defp encode_timetag(bin) when is_binary(bin) and byte_size(bin) == 8, do: bin

  defp decode_bundle(<<timetag::binary-size(8), rest::binary>>) do
    case decode_bundle_elements(rest, []) do
      {:ok, elements} -> {:ok, {:bundle, decode_timetag(timetag), elements}}
      {:error, _} = err -> err
    end
  end

  defp decode_bundle(_), do: {:error, :invalid}

  defp decode_timetag(@immediate_timetag), do: :immediate
  defp decode_timetag(bin), do: bin

  defp decode_bundle_elements(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_bundle_elements(<<size::signed-32-big, rest::binary>>, acc)
       when size > 0 and rem(size, 4) == 0 and byte_size(rest) >= size do
    <<elem::binary-size(size), rest2::binary>> = rest

    case decode(elem) do
      {:ok, decoded} -> decode_bundle_elements(rest2, [decoded | acc])
      {:error, _} = err -> err
    end
  end

  defp decode_bundle_elements(_, _), do: {:error, :invalid}

  defp decode_message(bin) do
    with {:ok, path, rest} <- decode_string(bin),
         {:ok, tags, rest} <- decode_string(rest),
         true <- String.starts_with?(tags, ","),
         {:ok, args, _rest} <- decode_args(String.slice(tags, 1..-1//1), rest, []) do
      {:ok, {:message, path, args}}
    else
      _ -> {:error, :invalid}
    end
  end

  defp decode_args("", rest, acc) when is_binary(rest), do: {:ok, Enum.reverse(acc), rest}

  defp decode_args(<<"i", tags::binary>>, <<v::signed-32-big, rest::binary>>, acc) do
    decode_args(tags, rest, [v | acc])
  end

  defp decode_args(<<"f", tags::binary>>, <<v::float-32-big, rest::binary>>, acc) do
    decode_args(tags, rest, [v | acc])
  end

  defp decode_args(<<"s", tags::binary>>, rest, acc) do
    case decode_string(rest) do
      {:ok, s, rest} -> decode_args(tags, rest, [s | acc])
      {:error, _} = err -> err
    end
  end

  defp decode_args(<<"b", tags::binary>>, rest, acc) do
    case decode_blob(rest) do
      {:ok, blob, rest} -> decode_args(tags, rest, [blob | acc])
      {:error, _} = err -> err
    end
  end

  defp decode_args(<<"T", tags::binary>>, rest, acc), do: decode_args(tags, rest, [true | acc])
  defp decode_args(<<"F", tags::binary>>, rest, acc), do: decode_args(tags, rest, [false | acc])
  defp decode_args(<<"N", tags::binary>>, rest, acc), do: decode_args(tags, rest, [nil | acc])
  defp decode_args(_, _, _), do: {:error, :invalid}

  defp decode_blob(<<size::signed-32-big, rest::binary>>) when size >= 0 do
    total = pad4(size)

    if byte_size(rest) >= total do
      <<blob::binary-size(size), _pad::binary-size(total - size), rest2::binary>> = rest
      {:ok, blob, rest2}
    else
      {:error, :invalid}
    end
  end

  defp decode_blob(_), do: {:error, :invalid}

  defp type_tag(v) when is_integer(v), do: "i"
  defp type_tag(v) when is_float(v), do: "f"
  defp type_tag(v) when is_binary(v), do: "s"
  defp type_tag(true), do: "T"
  defp type_tag(false), do: "F"
  defp type_tag(nil), do: "N"

  defp type_tag(other) do
    raise ArgumentError, "unsupported OSC type: #{inspect(other)}"
  end

  defp encode_arg(v) when is_integer(v) do
    <<clamp_int32(v)::signed-32-big>>
  end

  defp encode_arg(v) when is_float(v), do: <<v::float-32-big>>
  defp encode_arg(v) when is_binary(v), do: encode_string(v)
  defp encode_arg(true), do: []
  defp encode_arg(false), do: []
  defp encode_arg(nil), do: []

  defp clamp_int32(v) when v < -2_147_483_648, do: -2_147_483_648
  defp clamp_int32(v) when v > 2_147_483_647, do: 2_147_483_647
  defp clamp_int32(v), do: v

  defp encode_string(s) when is_binary(s) do
    total = pad4(byte_size(s) + 1)
    s <> :binary.copy(<<0>>, total - byte_size(s))
  end

  defp decode_string(bin) when is_binary(bin) do
    case :binary.match(bin, <<0>>) do
      {idx, 1} ->
        total = pad4(idx + 1)

        if byte_size(bin) >= total do
          {:ok, binary_part(bin, 0, idx), binary_part(bin, total, byte_size(bin) - total)}
        else
          {:error, :invalid}
        end

      :nomatch ->
        {:error, :invalid}
    end
  end

  defp pad4(n), do: div(n + 3, 4) * 4
end
