defmodule Core.FormulaStoreTest do
  @moduledoc false
  # async: false — @synced_table はグローバル ETS、LocalBackend は共有 Agent のため、
  # テスト間でリソースが干渉する。並列実行を避け、setup で初期化する。
  use ExUnit.Case, async: false

  alias Core.FormulaGraph
  alias Core.FormulaStore

  setup do
    Application.put_env(:core, :formula_store_broadcast, nil)
    FormulaStore.init()

    # LocalBackend は Server.Application で起動。core 単体テストでは未起動の可能性があるため起動
    case Process.whereis(Core.FormulaStore.LocalBackend) do
      nil ->
        start_supervised(Core.FormulaStore.LocalBackend)

      _ ->
        :ok
    end

    :ok
  end

  describe "synced" do
    test "read/write と merge_for_run, apply_updates" do
      room_id = :main
      FormulaStore.write_synced(room_id, "score", 10)
      FormulaStore.write_synced(room_id, "wave", 1)

      store_values = FormulaStore.merge_for_run(room_id, ["score", "wave"], [], %{})
      assert store_values["score"] == 10
      assert store_values["wave"] == 1

      # グラフで score+1 を計算して書き戻す
      graph = build_score_inc_graph()
      {:ok, {[11], store_list}} = FormulaGraph.run(graph, %{}, store_values)
      assert {"score", 11} in store_list

      FormulaStore.apply_updates(room_id, store_list, ["score", "wave"], [])

      assert FormulaStore.read_synced(room_id, "score", 0) == 11
    end

    test "未設定キーは context のデフォルトを使用" do
      room_id = :test_room

      store_values =
        FormulaStore.merge_for_run(
          room_id,
          ["score"],
          [],
          %{"score" => 0}
        )

      assert store_values["score"] == 0
    end
  end

  describe "local" do
    test "read/write と merge_for_run, apply_updates" do
      FormulaStore.write_local("pref", 42)
      store_values = FormulaStore.merge_for_run(:main, [], ["pref"], %{})
      assert store_values["pref"] == 42

      FormulaStore.apply_updates(:main, [{"pref", 99}], [], ["pref"])
      assert FormulaStore.read_local("pref", nil) == 99
    end
  end

  describe "apply_synced_from_network" do
    test "ネットワーク経由の更新を適用" do
      room_id = :peer_room
      FormulaStore.apply_synced_from_network(room_id, "shared_score", 100)
      assert FormulaStore.read_synced(room_id, "shared_score", 0) == 100
    end

    test "atom の key を文字列に正規化して保存" do
      room_id = :atom_key_room
      FormulaStore.apply_synced_from_network(room_id, :score, 42)
      assert FormulaStore.read_synced(room_id, "score", 0) == 42
    end
  end

  defp build_score_inc_graph do
    %FormulaGraph{
      nodes: [
        %{id: :r, op: :read_store, params: %{key: "score"}},
        %{id: :one, op: :int, params: %{value: 1}},
        %{id: :sum, op: :add, params: %{}},
        %{id: :w, op: :write_store, params: %{key: "score"}},
        %{id: :r2, op: :read_store, params: %{key: "score"}},
        %{id: :out, op: :output, params: %{}}
      ],
      edges: [
        {:r, :sum, :a},
        {:one, :sum, :b},
        {:sum, :w, :value},
        {:w, :r2, :after},
        {:r2, :out, :value}
      ],
      outputs: [:out]
    }
  end
end
