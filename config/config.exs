import Config

# 使用するコンテンツを指定する。
# GameContent.VampireSurvivor — ヴァンパイアサバイバークローン
# GameContent.AsteroidArena   — 小惑星シューター（武器・ボスなし）
config :game_server, :current, GameContent.VampireSurvivor
config :game_server, :map, :plain

# セーブデータの HMAC 署名鍵。
# 本番ビルド時は環境変数 SAVE_HMAC_SECRET で上書きすることを推奨する。
# ローカルゲームの性質上、完全な改ざん防止は不可能だが、
# 環境ごとに鍵を変えることで配布バイナリ間の互換性を制御できる。
config :game_engine, :save_hmac_secret,
  System.get_env("SAVE_HMAC_SECRET", "alchemy-engine-save-secret-v1")
