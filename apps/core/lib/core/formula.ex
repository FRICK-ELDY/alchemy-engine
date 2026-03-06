defmodule Core.Formula do
  @moduledoc """
  コンテンツ数式エンジンの Elixir 側ヘルパー。

  Phase 1 ではバイトコードの生成と NIF 呼び出しを提供する。
  Phase 3 で FormulaGraph からのコンパイルを追加予定。

  ## OpCode バイト値
  - 0: LOAD_INPUT
  - 1: LOAD_I32
  - 2: LOAD_F32
  - 3: LOAD_BOOL
  - 4: ADD, 5: SUB, 6: MUL, 7: DIV
  - 8: LT, 9: GT, 10: EQ
  - 11: STORE_OUTPUT
  """

  alias Core.NifBridge

  @doc """
  バイトコードを実行し、出力値のリストを返す。

  ## 例
      bytecode = Core.Formula.build([
        {:load_input, 0, "player_x"},
        {:load_input, 1, "player_y"},
        {:add, 2, 0, 1},
        {:store_output, 2}
      ])
      Core.Formula.run(bytecode, %{"player_x" => 1.0, "player_y" => 2.0})
      # => {:ok, [3.0]}
  """
  @spec run(binary(), map()) ::
          {:ok, [number() | boolean()]} | {:error, atom(), String.t() | integer() | nil}
  def run(bytecode, inputs) when is_binary(bytecode) and is_map(inputs) do
    NifBridge.run_formula_bytecode(bytecode, inputs)
  end

  @doc """
  命令リストからバイナリバイトコードを生成する。

  ## 制約
  - `LOAD_INPUT` の `name` は 255 バイト以下であること。超過時は `IO.iodata_to_binary/1` でランタイムエラーとなる。
  - 入力の integer は i32 範囲（-2^31 ～ 2^31-1）内であること。

  ## 命令形式
  - `{:load_input, dst, name}` - 入力 name をレジスタ dst へ
  - `{:load_i32, dst, value}` - 定数 i32 をレジスタ dst へ
  - `{:load_f32, dst, value}` - 定数 f32 をレジスタ dst へ
  - `{:load_bool, dst, value}` - 定数 bool をレジスタ dst へ
  - `{:add, dst, src_a, src_b}` - ADD
  - `{:sub, dst, src_a, src_b}` - SUB
  - `{:mul, dst, src_a, src_b}` - MUL
  - `{:div, dst, src_a, src_b}` - DIV
  - `{:lt, dst, src_a, src_b}` - LT
  - `{:gt, dst, src_a, src_b}` - GT
  - `{:eq, dst, src_a, src_b}` - EQ
  - `{:store_output, src}` - レジスタ src を出力へ
  """
  @spec build([tuple()]) :: binary()
  def build(instructions) do
    instructions
    |> Enum.flat_map(&encode_instruction/1)
    |> IO.iodata_to_binary()
  end

  defp encode_instruction({:load_input, dst, name}) when is_binary(name) do
    name_bin = name
    len = byte_size(name_bin)
    [0, dst, len] ++ :binary.bin_to_list(name_bin)
  end

  defp encode_instruction({:load_input, dst, name}) when is_atom(name) do
    encode_instruction({:load_input, dst, to_string(name)})
  end

  defp encode_instruction({:load_i32, dst, value}) when is_integer(value) do
    [1, dst] ++ :binary.bin_to_list(<<value::little-signed-integer-32>>)
  end

  defp encode_instruction({:load_f32, dst, value}) when is_number(value) do
    [2, dst] ++ :binary.bin_to_list(<<value::little-float-32>>)
  end

  defp encode_instruction({:load_bool, dst, value}) when is_boolean(value) do
    [3, dst, if(value, do: 1, else: 0)]
  end

  defp encode_instruction({:add, dst, src_a, src_b}), do: [4, dst, src_a, src_b]
  defp encode_instruction({:sub, dst, src_a, src_b}), do: [5, dst, src_a, src_b]
  defp encode_instruction({:mul, dst, src_a, src_b}), do: [6, dst, src_a, src_b]
  defp encode_instruction({:div, dst, src_a, src_b}), do: [7, dst, src_a, src_b]
  defp encode_instruction({:lt, dst, src_a, src_b}), do: [8, dst, src_a, src_b]
  defp encode_instruction({:gt, dst, src_a, src_b}), do: [9, dst, src_a, src_b]
  defp encode_instruction({:eq, dst, src_a, src_b}), do: [10, dst, src_a, src_b]
  defp encode_instruction({:store_output, src}), do: [11, src]
end
