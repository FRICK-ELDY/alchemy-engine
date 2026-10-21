# OSC Sample コンテンツで起動するための設定
# 使用例: mix run --config config/sample_osc.exs
import Config
import_config "config.exs"
config :server, :current, Content.SampleOsc
