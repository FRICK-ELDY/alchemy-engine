# P5-2 MessagePack — 動作確認・パフォーマンス計測 実施計画書

> 作成日: 2026-03-07  
> 出典: [p5-2-messagepack-execution-plan.md](p5-2-messagepack-execution-plan.md) タスク 11  
> 参照: [contents-defines-rust-executes.md](../plan/contents-defines-rust-executes.md) 保証の原則

---

## 1. 目的と保証との関係

本計画書は **製品の保証に関わる** 検証を定める。P5-2 MessagePack 移行は次の点で品質・性能を保証する前提となる。

| 保証対象 | 内容 |
|:---|:---|
| 機能保証 | MessagePack パスで描画結果がタプルパスと等価であること |
| 性能保証 | MessagePack パスがタプルパスと同等以上であること（回帰なし） |
| 再現性 | 計測条件・手順を文書化し、いつでも同様に検証できること |

実施前に本計画書を読み、計測方法・記録形式を共通認識とする。

---

## 2. 実施項目

### 2.1 動作確認

**目的**: MessagePack パスで描画が正しく行われることを確認する。

| 項目 | 内容 |
|:---|:---|
| 対象 | VampireSurvivor（MessagePack パスを使用） |
| 確認観点 | プレイヤー・敵・弾・パーティクル・アイテム・障害物・UI（HUD・レベルアップモーダル・ゲームオーバー）が崩れず描画されること |
| 記録 | 実施日時・環境・確認内容・スクリーンショット or メモ |

### 2.2 パフォーマンス計測

**目的**: MessagePack パスがタプルパスと同等以上の性能であることを定量的に示す。

| 計測対象 | 内容 |
|:---|:---|
| エンコード（Elixir） | `Content.MessagePackEncoder.encode_frame/4` の 1 フレームあたりの実行時間 |
| NIF 呼び出し全体 | `push_render_frame`（タプル）と `push_render_frame_binary`（MessagePack）の実時間差 |
| 比較 | MessagePack パス vs タプルパス（同一条件で計測） |

---

## 3. 実施方法

### 3.1 動作確認の手順

1. `config/config.exs` で `config :server, :current, Content.VampireSurvivor` を設定
2. `mix run --no-halt` で起動
3. 数分間プレイし、上記の確認観点を目視でチェック
4. [4.1 動作確認記録テンプレート](#41-動作確認記録テンプレート) に従って記録

### 3.2 パフォーマンス計測の手順

#### 方法 A: Benchee（Elixir エンコードのみ）

1. `bench/` ディレクトリに Benchee ベンチマークを追加
2. VampireSurvivor の典型的な 1 フレーム分（commands, camera, ui）のサンプルを用意
3. `Content.MessagePackEncoder.encode_frame/4` の実行時間を計測
4. 比較対象として、タプル形式をそのまま保持する処理（エンコードの実質オーバーヘッドなし）も計測

**成果物**: `mix run bench/bench.exs` で実行できるスクリプト

#### 方法 B: 実機プレイ + Telemetry

1. Telemetry で `on_nif_sync` や NIF 呼び出しの処理時間を記録
2. VampireSurvivor を MessagePack パスで数分間プレイ
3. タプルパスに一時切り替え、同条件で計測
4. 両者の分布（中央値・P95・最大値）を比較

**成果物**: 計測結果の表（後述テンプレート参照）

#### 方法 C: 併用（推奨）

- 方法 A でエンコード単体のオーバーヘッドを把握
- 方法 B で実フレーム時間への影響を把握

---

## 4. 記録テンプレート

### 4.1 動作確認記録テンプレート

```markdown
## 動作確認結果

| 項目 | 値 |
|:---|:---|
| 実施日 | YYYY-MM-DD |
| 環境 | OS / Elixir 版 / Rust 版 |
| コンテンツ | Content.VampireSurvivor |
| パス | MessagePack（push_render_frame_binary） |

### 確認観点

| 観点 | 結果 | 備考 |
|:---|:---:|:---|
| プレイヤースプライト | ○/× | |
| 敵スプライト | ○/× | |
| 弾・パーティクル | ○/× | |
| アイテム・障害物 | ○/× | |
| HUD（HP・EXP・スコア等） | ○/× | |
| レベルアップモーダル | ○/× | |
| ゲームオーバー画面 | ○/× | |

### 証跡

（スクリーンショット or メモを貼付 or 簡潔な記述）
```

### 4.2 パフォーマンス計測記録テンプレート

**読み手が一目で比較できる形式** とする。以下を推奨。

```markdown
## パフォーマンス計測結果

| 項目 | 値 |
|:---|:---|
| 実施日 | YYYY-MM-DD |
| 環境 | OS / CPU / Elixir 版 / Rust 版 |
| 計測方法 | Benchee / Telemetry / 両方 |

### エンコード時間（1フレームあたり）

| パス | 平均 (μs) | 中央値 (μs) | P95 (μs) | 備考 |
|:---|:---:|:---:|:---:|:---|
| MessagePack | — | — | — | encode_frame/4 |
| タプル（比較用） | — | — | — | 構造体組み立てのみ |

### NIF 呼び出し時間（1フレームあたり）

| パス | 平均 (μs) | 中央値 (μs) | P95 (μs) | 備考 |
|:---|:---:|:---:|:---:|:---|
| push_render_frame_binary | — | — | — | MessagePack |
| push_render_frame | — | — | — | タプル |

### まとめ（人間が読みやすい要約）

- MessagePack パスはタプルパスと比べて 〇〇% 速い / 遅い / ほぼ同等
- 実プレイでの体感差: あり / なし
- 推奨: MessagePack パスを採用 / 要検討
```

---

## 5. 実施後の更新

1. 本計画書の「記録テンプレート」以下に、実際の計測結果を追記する
2. `p5-2-messagepack-execution-plan.md` のタスク 11 を完了とする
3. 結果が保証に影響する場合は、`docs/warranty/` 等の関連ドキュメントへ参照を追加する

---

## 6. 参照

| ドキュメント | 内容 |
|:---|:---|
| [p5-2-messagepack-execution-plan.md](p5-2-messagepack-execution-plan.md) | 実行計画・残タスク |
| [messagepack-schema.md](../architecture/messagepack-schema.md) | スキーマ定義 |
| [contents-defines-rust-executes.md](../plan/contents-defines-rust-executes.md) | 保証の原則 |
| [ci.md](../warranty/ci.md) | CI による品質保証 |
