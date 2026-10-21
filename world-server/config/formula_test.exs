# FormulaTest コンテンツで起動するための設定
# 使用例: mix run --config config/formula_test.exs
import Config
import_config "config.exs"
config :server, :current, Content.FormulaTest
