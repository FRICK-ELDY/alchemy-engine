import Config

# 起動するゲームモジュールを指定
config :game_server, :current_game, GameContent.VampireSurvivor

# マップ設定
config :game_server, :map, :plain
