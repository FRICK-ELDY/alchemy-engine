import Config

# `config.exs` の `config :server, :current`（既定コンテンツ）を継承する。テストだけ別コンテンツにしたい場合はここで上書きする。
# テストでは Phoenix HTTP をリッスンしない（port 4000 の EADDRINUSE 回避。`mix test` と開発サーバー並行可）。
config :network, Network.Endpoint, server: false

# UDP は OS の空きポートに割り当て（4001 固定だと開発サーバー等と競合し EADDRINUSE になり得る）。
config :network, Network.UDP, port: 0

# FormulaStore のテストでは broadcast を無効化（Network への依存を避ける）
config :core, :formula_store_broadcast, nil

