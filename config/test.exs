import Config

# テストでは Phoenix HTTP をリッスンしない（port 4000 の EADDRINUSE 回避。`mix test` と開発サーバー並行可）。
config :network, Network.Endpoint, server: false

# FormulaStore のテストでは broadcast を無効化（Network への依存を避ける）
config :core, :formula_store_broadcast, nil

