defmodule Core.FormulaTest do
  use ExUnit.Case, async: true

  alias Core.Formula

  describe "run/3" do
    test "player_x + player_y を計算" do
      bytecode =
        Formula.build([
          {:load_input, 0, "player_x"},
          {:load_input, 1, "player_y"},
          {:add, 2, 0, 1},
          {:store_output, 2}
        ])

      assert {:ok, {[3.0], _}} = Formula.run(bytecode, %{"player_x" => 1.0, "player_y" => 2.0})
      assert {:ok, {[x], _}} = Formula.run(bytecode, %{"player_x" => -1.0, "player_y" => 1.0})
      assert abs(x - 0.0) < 1.0e-6
    end

    test "定数ロードと演算" do
      bytecode =
        Formula.build([
          {:load_i32, 0, 10},
          {:load_i32, 1, 3},
          {:add, 2, 0, 1},
          {:store_output, 2}
        ])

      assert {:ok, {[13], _}} = Formula.run(bytecode, %{})
    end

    test "比較 (lt)" do
      bytecode =
        Formula.build([
          {:load_input, 0, "a"},
          {:load_input, 1, "b"},
          {:lt, 2, 0, 1},
          {:store_output, 2}
        ])

      assert {:ok, {[true], _}} = Formula.run(bytecode, %{"a" => 1.0, "b" => 2.0})
      assert {:ok, {[false], _}} = Formula.run(bytecode, %{"a" => 2.0, "b" => 1.0})
    end

    test "存在しない入力名でエラー" do
      bytecode =
        Formula.build([
          {:load_input, 0, "missing"},
          {:store_output, 0}
        ])

      assert {:error, :input_not_found, "missing"} = Formula.run(bytecode, %{})
    end

    test "0 除算でエラー" do
      bytecode =
        Formula.build([
          {:load_i32, 0, 1},
          {:load_i32, 1, 0},
          {:div, 2, 0, 1},
          {:store_output, 2}
        ])

      assert {:error, :division_by_zero, nil} = Formula.run(bytecode, %{})
    end

    test "不正なオペコードでエラー" do
      # 不正なオペコード 99 を含むバイトコード
      bytecode = <<99>>
      assert {:error, :invalid_opcode, 99} = Formula.run(bytecode, %{})
    end

    test "未初期化レジスタ参照でエラー" do
      # r1 を初期化せずに store_output
      bytecode =
        Formula.build([
          {:store_output, 1}
        ])

      assert {:error, :type_mismatch, msg} = Formula.run(bytecode, %{})
      assert msg =~ "uninitialized"
    end

    test "レジスタ番号の範囲外でエラー" do
      # レジスタ 64 は範囲外（0-63 が有効）
      # LOAD_I32 r64, 0
      bytecode = <<1, 64, 0, 0, 0, 0>>
      assert {:error, :register_out_of_range, 64} = Formula.run(bytecode, %{})
    end

    test "Store の read/write" do
      # score を読んで 1 足して書き戻す
      bytecode =
        Formula.build([
          {:read_store, 0, "score"},
          {:load_i32, 1, 1},
          {:add, 2, 0, 1},
          {:write_store, 2, "score"},
          {:read_store, 3, "score"},
          {:store_output, 3}
        ])

      assert {:ok, {[1], store_list}} = Formula.run(bytecode, %{}, %{"score" => 0})
      assert {"score", 1} in store_list
    end

    test "Store に存在しないキーで read するとエラー" do
      bytecode =
        Formula.build([
          {:read_store, 0, "missing"},
          {:store_output, 0}
        ])

      assert {:error, :store_not_found, "missing"} =
               Formula.run(bytecode, %{}, %{})
    end
  end
end
