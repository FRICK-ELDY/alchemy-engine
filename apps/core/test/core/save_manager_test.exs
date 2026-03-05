defmodule Core.SaveManagerTest do
  use ExUnit.Case, async: false

  alias Core.SaveManager

  @save_dir Path.join(System.tmp_dir!(), "alchemy_engine_save_test")

  setup do
    # SaveManager テスト時に NIF をモックに差し替え
    Application.put_env(:core, :nif_bridge, Core.NifBridgeMock)
    Application.put_env(:core, :save_dir, @save_dir)

    on_exit(fn ->
      Application.delete_env(:core, :nif_bridge)
      Application.delete_env(:core, :save_dir)
    end)

    if File.exists?(@save_dir), do: File.rm_rf!(@save_dir)
    File.mkdir_p!(@save_dir)

    :ok
  end

  describe "save_high_score/1 and load_high_scores/0" do
    test "スコアを保存して読み戻せる" do
      assert SaveManager.save_high_score(100) == :ok
      assert SaveManager.load_high_scores() == [100]
    end

    test "複数スコアは降順で最大10件保持される" do
      SaveManager.save_high_score(50)
      SaveManager.save_high_score(200)
      SaveManager.save_high_score(100)
      assert SaveManager.load_high_scores() == [200, 100, 50]
    end

    test "11件以上登録時は上位10件のみ保持" do
      for i <- 1..12, do: SaveManager.save_high_score(i)
      assert length(SaveManager.load_high_scores()) == 10
      assert hd(SaveManager.load_high_scores()) == 12
    end

    test "負のスコアは :invalid_score エラー" do
      assert SaveManager.save_high_score(-1) == {:error, :invalid_score}
    end

    test "非整数は :invalid_score エラー" do
      assert SaveManager.save_high_score(3.14) == {:error, :invalid_score}
    end
  end

  describe "best_score/0" do
    test "スコアが無いとき nil" do
      assert SaveManager.best_score() == nil
    end

    test "最高スコアを返す" do
      SaveManager.save_high_score(50)
      SaveManager.save_high_score(100)
      assert SaveManager.best_score() == 100
    end
  end

  describe "save_session/2 and load_session/1（NIF Mock 使用）" do
    test "セッションの保存とロードが往復する" do
      world_ref = make_ref()

      snapshot = %{
        player_hp: 80.0,
        player_x: 100.0,
        player_y: 200.0,
        player_max_hp: 100.0,
        elapsed_seconds: 45.0
      }

      Mox.stub(Core.NifBridgeMock, :get_save_snapshot, fn ^world_ref -> snapshot end)
      Mox.stub(Core.NifBridgeMock, :load_save_snapshot, fn ^world_ref, _ -> :ok end)

      assert SaveManager.save_session(world_ref) == :ok
      assert SaveManager.has_save?()
      assert {:ok, state} = SaveManager.load_session(world_ref)
      assert state["player_hp"] == 80.0
      assert state["player_x"] == 100.0
      assert state["player_y"] == 200.0
      assert state["elapsed_seconds"] == 45.0
    end

    test "weapon_slots を opts で渡せる" do
      world_ref = make_ref()

      snapshot = %{
        player_hp: 100.0,
        player_x: 0.0,
        player_y: 0.0,
        player_max_hp: 100.0,
        elapsed_seconds: 0.0
      }

      Mox.stub(Core.NifBridgeMock, :get_save_snapshot, fn ^world_ref -> snapshot end)
      Mox.stub(Core.NifBridgeMock, :load_save_snapshot, fn ^world_ref, _ -> :ok end)

      assert SaveManager.save_session(world_ref, weapon_slots: [%{kind_id: 1, level: 2}]) == :ok
      assert {:ok, state} = SaveManager.load_session(world_ref)
      assert state["weapon_slots"] == [%{"kind_id" => 1, "level" => 2}]
    end
  end

  describe "HMAC 検証" do
    test "正当な HMAC 署名付きファイルは読み出せる" do
      SaveManager.save_high_score(999)
      assert SaveManager.load_high_scores() == [999]
    end

    test "改ざんされたファイルは読み出せず空リストとなる（payload 内の数値変更）" do
      SaveManager.save_high_score(100)
      path = Path.join(@save_dir, "high_scores.json")
      raw = File.read!(path)
      tampered = String.replace(raw, "100", "999")
      File.write!(path, tampered)

      assert SaveManager.load_high_scores() == []
    end

    test "改ざんされたファイルは読み出せず空リストとなる（HMAC 本体の偽装）" do
      SaveManager.save_high_score(50)
      path = Path.join(@save_dir, "high_scores.json")
      envelope = Jason.decode!(File.read!(path))
      # payload はそのままで HMAC だけ偽の値に差し替え
      tampered = Jason.encode!(Map.put(envelope, "hmac", "fake_hmac_base64_value"))
      File.write!(path, tampered)

      assert SaveManager.load_high_scores() == []
    end

    test "改ざんされたファイルは読み出せず空リストとなる（payload フィールド追加）" do
      SaveManager.save_high_score(200)
      path = Path.join(@save_dir, "high_scores.json")
      envelope = Jason.decode!(File.read!(path))
      payload = Jason.decode!(envelope["payload"])
      # state.scores を改ざん
      new_state = Map.put(payload["state"], "scores", [9999])
      new_payload = Map.put(payload, "state", new_state)

      tampered =
        Jason.encode!(%{"payload" => Jason.encode!(new_payload), "hmac" => envelope["hmac"]})

      File.write!(path, tampered)

      assert SaveManager.load_high_scores() == []
    end
  end

  describe "has_save?/0" do
    test "セーブが無いとき false" do
      refute SaveManager.has_save?()
    end

    test "セーブがあるとき true" do
      world_ref = make_ref()

      snapshot = %{
        player_hp: 50.0,
        player_x: 0.0,
        player_y: 0.0,
        player_max_hp: 100.0,
        elapsed_seconds: 10.0
      }

      Mox.stub(Core.NifBridgeMock, :get_save_snapshot, fn ^world_ref -> snapshot end)
      SaveManager.save_session(world_ref)
      assert SaveManager.has_save?()
    end
  end

  describe "load_session/1" do
    test "セーブが無いとき :no_save" do
      assert SaveManager.load_session(make_ref()) == :no_save
    end
  end
end
