import Config

# FormulaStore のテストでは broadcast を無効化（Network への依存を避ける）
config :core, :formula_store_broadcast, nil

# SaveManager の保存先を一時ディレクトリに固定（ユーザーの実セーブデータを汚染しない）。
# save_manager_test.exs の setup でも同じパスを put_env しているが、本設定は他テストが
# SaveManager を呼ぶ場合のフォールバックとなる。SaveManager テストは setup で上書きし、
# テスト間のファイル干渉を防ぐため一時ディレクトリをクリアしてから使用する。
config :core, :save_dir, Path.join(System.tmp_dir!(), "alchemy_engine_save_test")
