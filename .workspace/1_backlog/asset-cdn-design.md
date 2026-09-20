# アセット配信設計 — CDN対応 & ローカル参照スキーム & 暗号化パッケージ

> 作成日: 2026-03-02  
> 目的: アセット（スプライト・音声）の所在管理をElixir/Rust双方から疎結合に保ちつつ、Cloudflare R2等のCDNとローカルファイルシステムを統一的に参照できる設計を定義する。また、アセットを暗号化パッケージ（`.alchemypackage`）としてローカルキャッシュし、不正な直接参照を防ぐ。

---

## 背景と設計方針

### 3者の責務分離

| レイヤー | 責務 | アセットとの関係 |
|:---|:---|:---|
| **Elixir (contents)** | 「どのアセットセットを使うか」の意思決定 | 論理ID（`"vampire_survivor"`）のみ保持 |
| **NIF境界** | パス文字列の受け渡し | バイナリは一切通さない（NIFシリアライズ負荷ゼロ） |
| **Rust (AssetLoader)** | アセット実体の取得・キャッシュ | URIを解釈してバイト列を返す |

ElixirはアセットのバイナリをNIF越しに渡さない。  
RustはElixirのビジネスロジックを知らない。  
**両者の接点はURI文字列1本のみ。**

---

## アセットURIスキーム

アセットの所在を表すURIを以下の2スキームで統一する。

### `local://` — ローカルファイルシステム参照

```
local://assets/vampire_survivor/sprites/atlas.png
local://assets/vampire_survivor/audio/bgm.wav
local://assets/sprites/atlas.png          # ゲーム共通アセット
```

- `local://` 以降のパスは **プロジェクトルート（または `ASSETS_PATH` 環境変数）からの相対パス**として解釈する
- 開発中・CI・オフライン環境で使用する
- ファイルが存在しない場合は `include_bytes!` 埋め込みフォールバックを使用する

### `https://` — CDN参照（Cloudflare R2等）

```
https://assets.yourgame.com/vampire_survivor/sprites/atlas.png
https://pub-xxxx.r2.dev/vampire_survivor/audio/bgm.wav
```

- 本番環境・配布時に使用する
- Rustが直接HTTPで取得する（Elixirは関与しない）
- Cloudflare R2のカスタムドメインまたは `r2.dev` サブドメインを使用する

---

## Cloudflare R2 について

### 概要

Cloudflare R2はS3互換のオブジェクトストレージ。  
**エグレス（ダウンロード転送量）が無料**という点がゲームアセット配信に最適。

### 料金（2026年現在）

| 項目 | 料金 |
|:---|:---|
| ストレージ | $0.015/GB/月 |
| アップロード（Class A） | $4.50/百万リクエスト |
| ダウンロード（Class B） | $0.36/百万リクエスト |
| **エグレス（転送量）** | **無料** |

### 無料枠

| 項目 | 無料枠/月 |
|:---|:---|
| ストレージ | 10GB |
| Class A（アップロード） | 100万回 |
| Class B（ダウンロード） | 1,000万回 |

ゲームアセットは一度ダウンロード後にキャッシュされるため、  
無料枠で十分賄える可能性が高い。

### 公開方法

| 方法 | 用途 | URL例 |
|:---|:---|:---|
| `r2.dev` サブドメイン | 開発・検証 | `https://pub-xxxx.r2.dev/...` |
| カスタムドメイン | 本番 | `https://assets.yourgame.com/...` |

カスタムドメインを使用すると、Cloudflareの300+拠点でCDNキャッシュが有効になる。

---

## `.alchemypackage` — 暗号化アセットパッケージ

### 概要

CDNからダウンロードしたアセットは、ローカルに**暗号化パッケージ**として保存する。  
生のPNG/WAVファイルをそのままディスクに置かず、不正な直接参照・抽出を防ぐ。

```
~/.cache/alchemy-engine/
└── vampire_survivor.alchemypackage   ← 暗号化済みパッケージ
```

### パッケージフォーマット

`.alchemypackage` は以下の構造を持つ単一バイナリファイル。

```
┌─────────────────────────────────────────────────────────┐
│  Magic bytes: b"ALCH" (4 bytes)                         │
│  Version: u8 (1 byte)                                   │
│  Game ID length: u16 (2 bytes)                          │
│  Game ID: UTF-8 string (可変長)                          │
│  Entry count: u32 (4 bytes)                             │
├─────────────────────────────────────────────────────────┤
│  Entry[0]:                                              │
│    Asset ID: u8 (1 byte)                                │
│    Nonce: 12 bytes (AES-256-GCM)                        │
│    Ciphertext length: u32 (4 bytes)                     │
│    Ciphertext + Auth tag: 可変長                         │
│  Entry[1]: ...                                          │
│  ...                                                    │
└─────────────────────────────────────────────────────────┘
```

- 暗号化アルゴリズム: **AES-256-GCM**（認証付き暗号。改ざん検知も兼ねる）
- 各エントリは独立したNonceを持つ（エントリごとに異なる乱数）
- Auth tagにより復号時に改ざんを検知できる

### 鍵管理

| 環境 | 鍵の取得方法 |
|:---|:---|
| 開発中 | 環境変数 `ALCHEMY_ASSET_KEY`（hex文字列 64文字） |
| 本番 | Elixirサーバーが認証済みクライアントに配布（将来設計） |

> **注意:** 鍵をソースコードやリポジトリにコミットしない。`.env` ファイルは `.gitignore` に含める。

### キャッシュディレクトリ

| OS | デフォルトパス |
|:---|:---|
| Linux / macOS | `~/.cache/alchemy-engine/{game_id}.alchemypackage` |
| Windows | `%LOCALAPPDATA%\alchemy-engine\{game_id}.alchemypackage` |

Rustの `dirs` クレートで各OS標準のキャッシュディレクトリを取得する。  
環境変数 `ALCHEMY_CACHE_DIR` で上書き可能にする（CI・テスト用）。

### ライフサイクル

```
起動時
  ↓
.alchemypackage が存在する？
  ├─ Yes → バージョン/整合性チェック → OK なら使用
  │                                  → NG なら再ダウンロード
  └─ No  → CDN から全アセットをダウンロード
              ↓
           AES-256-GCM で暗号化
              ↓
           .alchemypackage として保存
              ↓
           使用
```

### ローカル開発時の扱い

`local://` スキームを使用する場合はパッケージ化をスキップし、  
生ファイルを直接読む（開発効率優先）。

```
local://  → 生ファイルを直接読む（暗号化なし）
https://  → ダウンロード → 暗号化 → .alchemypackage に保存 → 復号して使用
```

---

## 実装ロードマップ

### Phase A-1: `AssetLoader` をURIスキーム対応に拡張する

**影響クレート**: `audio`（将来的には `assets` クレートに分離）

現在の `AssetLoader` はファイルパス文字列のみを扱う。  
これをURIを受け取って解釈する形に変更する。

```rust
// 変更後のイメージ
impl AssetLoader {
    pub fn load_from_uri(&self, uri: &str) -> Vec<u8> {
        if let Some(path) = uri.strip_prefix("local://") {
            // ローカルファイルシステムから取得（暗号化なし）
            self.load_from_local_path(path)
        } else if uri.starts_with("https://") || uri.starts_with("http://") {
            // .alchemypackage キャッシュ → なければCDNからダウンロード＆暗号化保存
            self.load_from_package_or_cdn(uri)
        } else {
            // 旧来のパス文字列（後方互換）
            self.load_from_local_path(uri)
        }
    }
}
```

**作業ステップ:**
1. `AssetLoader` に `load_from_uri(&str) -> Vec<u8>` メソッドを追加する
2. `local://` プレフィックスをストリップしてローカルパスとして解釈する処理を実装する
3. `https://` の場合は Phase A-1.5 で実装する `AlchemyPackage` を経由して取得する
4. 既存の `load_bytes(AssetId)` は `load_from_uri(id.default_uri())` に委譲するよう変更する
5. `AssetId::default_uri()` を追加し、`"local://assets/sprites/atlas.png"` 形式で返すよう変更する

---

### Phase A-1.5: `.alchemypackage` の実装

**影響クレート**: `game_assets`（新規クレート、Phase A-3 と同時に作成）

**追加する依存クレート:**

| クレート | 用途 |
|:---|:---|
| `aes-gcm` | AES-256-GCM 暗号化・復号 |
| `rand` | Nonce生成（`OsRng`） |
| `reqwest`（blocking feature） または `ureq` | CDN HTTPダウンロード |
| `dirs` | OS標準キャッシュディレクトリ取得 |

**実装するモジュール構成:**

```
native/game_assets/src/
├── lib.rs
├── asset_id.rs          # AssetId enum・default_uri()
├── loader.rs            # AssetLoader（URI解釈・ディスパッチ）
├── package/
│   ├── mod.rs           # AlchemyPackage（読み書き）
│   ├── format.rs        # バイナリフォーマット定義
│   ├── encrypt.rs       # AES-256-GCM 暗号化・復号
│   └── cache_dir.rs     # キャッシュディレクトリ解決
└── cdn.rs               # CDN HTTPダウンロード
```

**`AlchemyPackage` の主要API（案）:**

```rust
impl AlchemyPackage {
    /// キャッシュディレクトリから既存パッケージを開く。存在しなければ None。
    pub fn open(game_id: &str, key: &[u8; 32]) -> Option<Self>;

    /// CDN から全アセットをダウンロードして暗号化パッケージを作成・保存する。
    pub fn download_and_create(
        game_id: &str,
        cdn_base_url: &str,
        key: &[u8; 32],
    ) -> Result<Self, PackageError>;

    /// パッケージから指定アセットを復号して返す。
    pub fn load(&self, id: AssetId) -> Result<Vec<u8>, PackageError>;

    /// パッケージのバージョン・整合性を検証する。
    pub fn verify(&self) -> bool;
}
```

**鍵の取得（`AssetLoader` 側）:**

```rust
fn load_asset_key() -> Option<[u8; 32]> {
    let hex = std::env::var("ALCHEMY_ASSET_KEY").ok()?;
    let bytes = hex::decode(&hex).ok()?;
    bytes.try_into().ok()
}
```

**作業ステップ:**
1. `aes-gcm`, `rand`, `ureq`（または `reqwest`）, `dirs`, `hex` を `game_assets/Cargo.toml` に追加する
2. `package/format.rs` にバイナリフォーマット定義（Magic bytes, Version, Entry構造体）を実装する
3. `package/encrypt.rs` に AES-256-GCM の暗号化（`encrypt`）・復号（`decrypt`）関数を実装する
4. `package/cache_dir.rs` に OS別キャッシュディレクトリ解決ロジックを実装する（`dirs::cache_dir()` 使用）
5. `cdn.rs` に CDN URL からバイト列をダウンロードする関数を実装する
6. `package/mod.rs` に `AlchemyPackage::open` / `download_and_create` / `load` / `verify` を実装する
7. `loader.rs` の `load_from_package_or_cdn` がパッケージキャッシュを確認し、なければダウンロード・作成するフローを実装する
8. `ALCHEMY_ASSET_KEY` が未設定の場合は暗号化をスキップして生ファイルをキャッシュするフォールバックを実装する（開発時の利便性）
9. `AlchemyPackage` のユニットテストを `package/mod.rs` に追加する（暗号化→復号の往復テスト・改ざん検知テスト）

---

### Phase A-2: Elixir側のパス解決をURI形式に統一する

**影響アプリ**: `core`, `contents`

現在の `resolve_atlas_path/1` が返す文字列をURI形式に変更する。

```elixir
# 変更後のイメージ
defp resolve_atlas_uri(content) do
  game_assets_id = ...

  case System.get_env("GAME_ASSETS_CDN_URL") do
    nil ->
      # ローカル参照
      base = System.get_env("ASSETS_PATH") || System.get_env("GAME_ASSETS_PATH") || "."
      if game_assets_id do
        "local://#{base}/assets/#{game_assets_id}/sprites/atlas.png"
      else
        "local://#{base}/assets/sprites/atlas.png"
      end

    cdn_url ->
      # CDN参照
      if game_assets_id do
        "#{cdn_url}/#{game_assets_id}/sprites/atlas.png"
      else
        "#{cdn_url}/sprites/atlas.png"
      end
  end
end
```

**環境変数の整理:**

| 環境変数 | 役割 | 例 |
|:---|:---|:---|
| `ASSETS_PATH` | ローカルアセットのベースディレクトリ | `/opt/app/assets` |
| `ASSETS_ID` | コンテンツ別サブディレクトリ名 | `vampire_survivor` |
| `GAME_ASSETS_CDN_URL` | CDNのベースURL（設定時はCDN優先） | `https://assets.yourgame.com` |

**作業ステップ:**
1. `game_events.ex` の `resolve_atlas_path/1` を `resolve_atlas_uri/1` にリネームし、URI形式を返すよう変更する
2. `GAME_ASSETS_CDN_URL` 環境変数が設定されている場合はCDN URLを優先するロジックを追加する
3. `server/application.ex` の `ASSETS_ID` セット処理はそのまま維持する
4. `nif_bridge.ex` / `core.ex` のシグネチャは変更不要（文字列を渡すだけのため）

---

### Phase A-3: `AssetLoader` を独立クレートに分離する

**影響クレート**: `audio`, `render`, `nif`

現在 `AssetLoader` は `audio` クレートに置かれているが、  
音声以外のアセット（スプライトアトラス）も管理しており責務が混在している。

```
# 現状（問題）
audio/src/asset/mod.rs  ← AssetLoader がここにある
render  ─────────────── audio に依存してアトラスを取得
nif     ─────────────── audio に依存して AssetLoader を使用

# 目標
game_assets/src/lib.rs  ← AssetLoader をここに移動
audio   ──────────── assets に依存
render  ──────────── assets に依存
nif     ──────────── assets に依存
```

**作業ステップ:**
1. `native/game_assets/` クレートを新規作成する（`Cargo.toml` に `[lib]` のみ）
2. `audio/src/asset/` を `assets/src/` に移動する
3. `audio/Cargo.toml` に `assets` への依存を追加し、`asset` モジュールの `pub use` を `assets` に委譲する
4. `render/Cargo.toml` と `nif/Cargo.toml` の依存を `audio` → `assets` に変更する
5. `nif/src/lib.rs` の `use audio::{AssetId, AssetLoader, ...}` を `use assets::{AssetId, AssetLoader}` に変更する

---

### Phase A-4: Ash Framework との統合（DB管理アセットメタデータ）

**前提**: Ash Framework 導入後に着手する

アセットの「実体」はファイルシステム/CDNに置き続けるが、  
「どのアセットセットを使うか」という設定をDBで管理できるようにする。

**Ashリソース設計（案）:**

```elixir
# コンテンツ別アセット設定
defmodule AlchemyEngine.Assets.ContentAssetConfig do
  use Ash.Resource, domain: AlchemyEngine.Assets

  attributes do
    uuid_primary_key :id
    attribute :content_id, :string, allow_nil?: false  # "vampire_survivor"
    attribute :assets_id, :string, allow_nil?: false   # "vampire_survivor"
    attribute :cdn_base_url, :string                   # nil = ローカル参照
    attribute :atlas_uri, :string                      # 解決済みURI（キャッシュ）
  end
end

# ユーザー別カスタムアセット（将来）
defmodule AlchemyEngine.Assets.UserAsset do
  use Ash.Resource, domain: AlchemyEngine.Assets

  attributes do
    uuid_primary_key :id
    attribute :user_id, :uuid, allow_nil?: false
    attribute :asset_type, :atom, allow_nil?: false    # :avatar, :skin, etc.
    attribute :uri, :string, allow_nil?: false         # local:// or https://
  end
end
```

**DBに入れるもの / 入れないもの:**

| 種別 | DBに入れるか | 理由 |
|:---|:---|:---|
| アセットの実体（PNG/WAVバイナリ） | **入れない** | 容量・パフォーマンス |
| アセットのURI（パス・URL文字列） | **入れる** | 設定の永続化・ユーザー別管理 |
| ゲーム別アセットセットID | **入れる** | コンテンツ設定の管理 |
| CDNベースURL | **入れる** | 環境別設定の管理 |

**作業ステップ:**
1. `AlchemyEngine.Assets` ドメインを `contents` アプリに追加する
2. `ContentAssetConfig` リソースを定義する
3. `contents` の `assets_path/0` をDB参照に切り替える（環境変数フォールバック維持）
4. `UserAsset` リソースを定義する（ユーザー別スキン機能実装時）

---

## 作業順序まとめ

```
A-1   AssetLoader を URI スキーム対応に拡張する
  ↓
A-1.5 .alchemypackage の実装（AES-256-GCM 暗号化キャッシュ）
  ↓
A-2   Elixir 側のパス解決を URI 形式に統一する
  ↓
A-3   AssetLoader を独立クレート（game_assets）に分離する
  ↓
A-4   Ash Framework との統合（DB管理アセットメタデータ）
```

A-1〜A-3 はリファクタリングであり、既存の動作を変えない。  
A-1.5 は新機能（暗号化キャッシュ）だが `local://` 利用時は従来通り動作する。  
A-4 は Ash Framework 導入後の新機能追加となる。

---

## 完了済みタスク

（なし）
