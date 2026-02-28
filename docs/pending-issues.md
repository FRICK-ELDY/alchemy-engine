# AlchemyEngine — 残課題・懸念点

> `vision.md` が定義する Engine / World / Rule の 3 層分離を完成させることが最終目標。
> このドキュメントは未解決の課題と将来への懸念点を管理する。
> 課題が解消されたら該当セクションを削除すること。

---

## 新しいコンテンツを追加する際の手順

2つ目のコンテンツを追加する場合は、以下の手順に従うこと。

1. `WorldBehaviour` を実装した新モジュールを作成し、`setup_world_params/1` で `set_entity_params` NIF に新コンテンツのエンティティパラメータを注入する
2. `RuleBehaviour` を実装した新モジュールを作成する（`initial_weapons/0`、`update_boss_ai/2`、`on_entity_removed/4` 等を含む）
3. `config :game_server, current_world: NewWorld, current_rule: NewRule` を設定する
4. I-2・I-5（`improvement-plan.md` 参照）を実施して、エンジンコアから VampireSurvivor 固有の概念を除去する

---

### 課題9: クラウドセーブ（独自サーバーによるセーブデータ同期）

**優先度**: 低（`game_network` の実装が前提）

**背景**

フェーズ1として `SaveManager` を OS 標準ディレクトリへの JSON 保存 + HMAC 署名に移行済み。
フェーズ2として、ユーザーアカウントに紐付いたクラウドセーブを実現し、複数端末間でのセーブデータ同期を可能にする。

**目標**

- ユーザーログイン（JWT 認証）によりセーブデータをサーバーに保存・取得できる
- ローカルとクラウドの競合を `saved_at` タイムスタンプで解決する
- オフライン時はローカル保存のみで動作し、オンライン復帰時に自動同期する

**設計方針**

`SaveStorage` behaviour を定義し、ストレージ実装を差し替え可能にする：

```elixir
defmodule GameEngine.SaveStorage do
  @callback save(path :: String.t(), data :: map()) :: :ok | {:error, term()}
  @callback load(path :: String.t()) :: {:ok, map()} | {:error, term()} | :not_found
  @callback delete(path :: String.t()) :: :ok | {:error, term()}
end

# フェーズ1（実装済み）
defmodule GameEngine.SaveStorage.Local do
  @behaviour GameEngine.SaveStorage
  # File.write! / File.read! ベースの実装
end

# フェーズ2（game_network 側に実装）
defmodule GameNetwork.SaveStorage.Cloud do
  @behaviour GameEngine.SaveStorage
  # Phoenix Channel / HTTP API 経由の実装
end
```

`SaveManager` は `config.exs` の設定でストレージ実装を切り替える：

```elixir
config :game_engine, :save_storage, GameEngine.SaveStorage.Local
# クラウド有効時:
# config :game_engine, :save_storage, GameNetwork.SaveStorage.Cloud
```

競合解決は `saved_at` タイムスタンプの比較で行う：
- ローカルが新しい → クラウドにアップロード
- クラウドが新しい → ローカルに上書きダウンロード

**依存・前提条件**

- `game_network` の Phoenix Channel / HTTP クライアント実装（課題7 相当）
- JWT 認証基盤（ユーザー登録・ログイン API）
- サーバー側のセーブデータ保存 DB（PostgreSQL 等）

**影響ファイル**

- `apps/game_engine/lib/game_engine/save_manager.ex` — `SaveStorage` behaviour 対応
- `apps/game_network/lib/game_network.ex` — `CloudStorage` 実装追加
- `apps/game_engine/mix.exs` — `game_network` への依存追加（クラウド有効時）
- `config/config.exs` — `:save_storage` 設定追加

---

### 課題10: Elixir の真価（OTP・並行性・分散）が活かされていない

**優先度**: 中（I-2・I-5 完了後に着手推奨）

**背景**

Elixir を選んだ最大の理由は「OTP による耐障害性」「軽量プロセスによる大規模並行性」「分散ノード間通信」だが、現状の実装ではこれらがほとんど活かされていない。

**問題1: NIF クラッシュが OTP の耐障害性を無効化している**

OTP の Supervisor ツリーは「プロセスが落ちても再起動できる」ことを保証するが、Rustler NIF がパニックすると BEAM VM ごと落ちる。現状は `load.rs` でパニックフックを設定しているものの、NIF 内の未捕捉パニックは依然として致命的である。

```
Supervisor
  └── GameEvents (GenServer)
        └── NIF 呼び出し → Rust パニック → BEAM VM クラッシュ
                                            ↑ Supervisor が再起動できない
```

目標: Rust 側のパニックを `Result` で返し、Elixir 側で `{:error, reason}` として受け取れるようにする。

対応:
1. `game_nif` の各 NIF 関数の戻り値を `NifResult<T>` に統一し、`unwrap()` / `expect()` を除去する
2. `physics_step` 内でパニックが起きうる箇所（配列アクセス等）を `get()` による境界チェックに置き換える
3. Elixir 側 `GameEvents` で NIF エラーを受け取った場合の回復ロジックを追加する（ゲームループ再起動等）

**問題2: 並行性が活かされていない（1ルームのみ稼働）**

`RoomSupervisor` と `Registry` は複数ルームの同時稼働を想定した設計になっているが、実際には `:main` ルーム 1 つしか起動していない。

目標: 複数ルームを同時稼働させ、各ルームが独立した `GameEvents` プロセスとして動作することを確認する。

対応:
1. `RoomSupervisor.start_room/1` を複数回呼び出して複数ルームを起動するテストを書く
2. 各ルームが独立した `GameWorld` リソース（Rust 側）を持つことを確認する
3. `game_network` のローカル PubSub 実装と組み合わせて、ルーム間通信を実装する

**問題3: `game_network` が未実装のため Elixir を選んだ理由が証明されていない**

Elixir + Phoenix Channels の組み合わせはリアルタイムマルチプレイヤーゲームの通信基盤として業界実績があるが、現状では `game_network.ex` が空のスタブである。

目標: `game_network` に最低限の PubSub 実装を追加し、同一 BEAM ノード上での複数プレイヤー同期を実現する。

対応:
1. `GameNetwork.Behaviour` ビヘイビアを定義する
2. `GameNetwork.Local` モジュールで `Registry` + `Phoenix.PubSub` を使ったローカル実装を作る
3. `GameEvents` が `EventBus` 経由でルーム状態を `GameNetwork` にブロードキャストする仕組みを追加する

**作業ステップ**

1. **問題1（NIF 安全性）**: `game_nif` の全 NIF 関数の戻り値を `NifResult<T>` に統一する（1〜2日）
2. **問題2（複数ルーム）**: 複数ルーム同時稼働の統合テストを書く（半日）
3. **問題3（game_network）**: I-4 フェーズ2 として `GameNetwork.Local` を実装する（2〜3日）

**影響ファイル**

- `native/game_nif/src/nif/*.rs` — 全 NIF 関数の `NifResult<T>` 統一
- `apps/game_engine/lib/game_engine/game_events.ex` — NIF エラー回復ロジック
- `apps/game_network/lib/game_network.ex` — `GameNetwork.Local` 実装

---

### 課題11: `game_network` が完全スタブ

**優先度**: 低（課題10 完了後・長期）

**背景**

マルチプレイヤー通信は設計思想の重要な柱だが、`apps/game_network/lib/game_network.ex` は実装なしのスタブである。Elixir + Phoenix Channels の組み合わせはリアルタイムマルチプレイヤーゲームの通信基盤として業界実績があるが、現状では未実証のままである。

**段階的な実装方針**

フェーズ1: インターフェース定義

`game_network` が提供すべき責務をビヘイビアとして定義する：

```elixir
defmodule GameNetwork.Behaviour do
  @callback broadcast_state(room_id :: atom(), state :: map()) :: :ok
  @callback send_to_player(player_id :: term(), message :: term()) :: :ok
  @callback subscribe_room(room_id :: atom()) :: :ok
  @callback list_players(room_id :: atom()) :: [term()]
end
```

フェーズ2: ローカルマルチプレイヤー（同一 BEAM ノード）

Phoenix Channels を使わずに、Elixir の `Registry` と `PubSub` を使ったローカルマルチプレイヤーを実装する。ネットワーク層なしでマルチプレイヤーのゲームロジックを検証できる。

フェーズ3: ネットワーク対応

| 方式 | 遅延 | 実装コスト | 適用場面 |
|:---|:---|:---|:---|
| Phoenix Channels (WebSocket) | 中 | 低 | ターン制・低速アクション |
| UDP (gen_udp) | 低 | 高 | リアルタイムアクション |
| Phoenix Channels + Delta 圧縮 | 中 | 中 | 現実的な妥協点 |

**作業ステップ**

1. `game_network.ex` に `GameNetwork.Behaviour` ビヘイビアを定義する
2. `GameNetwork.Local` モジュールを作成し、ローカル PubSub で動作するスタブ実装を提供する
3. `GameEvents` が `EventBus` 経由でルーム状態を `GameNetwork` にブロードキャストする仕組みを追加する
4. Phoenix Channels / UDP によるネットワーク対応を実装する

**影響ファイル**

- `apps/game_network/lib/game_network.ex` — `GameNetwork.Behaviour` 定義・`GameNetwork.Local` 実装
- `apps/game_engine/lib/game_engine/game_events.ex` — `GameNetwork` へのブロードキャスト追加
- `apps/game_engine/mix.exs` — `game_network` への依存追加（フェーズ2以降）

---

*このドキュメントは `vision.md` の思想に基づいて管理すること。*
*各課題の詳細な改善方針・作業ステップは [`improvement-plan.md`](./improvement-plan.md) を参照すること。*
