# シェーダー読み込みの Path Traversal 対策設計（P4-S）

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) P4-S  
> 参照: CWE-22 (Path Traversal)、[shader-elixir-interface.md](shader-elixir-interface.md)

---

## 1. 問題の特定

### 1.1 対象関数

`load_shaders_from_atlas_path`（`native/nif/src/render_bridge.rs`）および
`load_atlas_png`（同ファイル）が、`atlas_path` をそのまま利用してファイルを読み込んでいる。

### 1.2 脆弱性の内容

`atlas_path` に `..` 等を含むと、想定外のディレクトリのファイルを読み込む可能性がある（CWE-22: Path Traversal）。

**攻撃ベクトル例**:

| 入力元 | 悪意のある値の例 | 結果 |
|:---|:---|:---|
| Elixir `resolve_atlas_path` | `content.assets_path()` が `../../../etc` を返す | `assets/../../../etc/sprites/atlas.png` → 上位ディレクトリへ |
| 環境変数 `ASSETS_PATH` | `ASSETS_PATH=/etc` | システムディレクトリをベースに |
| 将来: ユーザー入力 | 不信頼ソースからパスを受け取る場合 | 任意ファイル読み取り |

現状、`atlas_path` は Elixir の `resolve_atlas_path(content)` から渡され、`content.assets_path()` はプロジェクト内のモジュールが返すため、**信頼境界は比較的狭い**。ただし、以下を理由に防御を追加することを推奨する:

- **Defense in Depth**: 上位層のバグや将来の変更で不正パスが渡っても、下位層でブロックできる
- **将来のサンドボックス化**: 不信頼コンテンツ利用時に、パス検証が必須となる

---

## 2. 対策方針

### 2.1 基本原則

1. **正規化**: パスを canonical 形式に変換し、`..` やシンボリックリンクの解決を行う
2. **検証**: 解決後のパスが**許可されたベースディレクトリ以下**に収まっていることを確認する
3. **ホワイトリスト**: 読み込み対象ファイル名を固定（`sprite.wgsl`, `mesh.wgsl`, `atlas.png`）し、ユーザー指定のファイル名は使わない

### 2.2 信頼境界の整理

| レイヤー | 責務 |
|:---|:---|
| **Elixir** | `resolve_atlas_path` で atlas_path を構築。`content.assets_path()` はコンテンツモジュールから取得（現状は信頼） |
| **Rust** | 受け取った atlas_path を**検証**し、許可範囲内のファイルのみ読み込む |

---

## 3. 実装案

### 3.1 ディレクトリ境界の検証

**方針**: `std::fs::canonicalize` でパスを正規化し、**ベースディレクトリ（作業ディレクトリまたは ASSETS_PATH 相当）の canonical パス**以下に収まるかチェックする。

```
実装の流れ:
1. atlas_path を Path として受け取る
2. atlas_path の親ディレクトリ（存在する場合）を canonicalize
3. カレントディレクトリ（または設定可能なベース）を canonicalize
4. 2 の結果が 3 の結果の接頭辞であることを確認（starts_with）
5. シェーダー読み込み時は d.join("sprite.wgsl") 等の固定ファイル名のみ使用
```

**制約**:
- `canonicalize` は**パスが存在する必要がある**。atlas.png が存在しない場合（埋め込みフォールバック時）、親ディレクトリの存在を確認できない場合がある
- その場合は「パスに `..` や絶対パスが含まれていないか」の簡易チェックにフォールバックする

### 3.2 簡易チェック（フォールバック）

パスが存在しない場合の代替策:

- `Path::components()` を走査し、`Component::ParentDir` が含まれる場合は拒否
- 絶対パスが渡された場合、ベースディレクトリからの相対関係を満たすか検証
- `assets_id` や `ASSETS_PATH` に `/` や `\` が含まれる場合は Elixir 側で拒否（オプション）

### 3.3 ファイル名のホワイトリスト

`load_shaders_from_atlas_path` 内では、`try_load(name)` の `name` は `"sprite.wgsl"` と `"mesh.wgsl"` に固定。ユーザー入力のファイル名は使わない。→ **現状で既に満たされている**。

### 3.4 推奨実装ステップ

| 優先度 | 内容 |
|:---|:---|
| **Phase 1** | パスに `..` が含まれる場合はログを出してフォールバック（include_str!）に切り替え。読み込みは行わない |
| **Phase 2** | atlas_path の親が存在する場合、`canonicalize` で正規化し、カレントディレクトリ（または `std::env::current_dir`）の canonical 以下か検証。違反時はフォールバック |
| **Phase 3** | 将来のサンドボックス化に備え、ベースディレクトリを設定可能にする |

---

## 4. 影響範囲

| ファイル | 変更内容 |
|:---|:---|
| `native/nif/src/render_bridge.rs` | `load_shaders_from_atlas_path` にパス検証を追加。`load_atlas_png` にも同様の検証を追加 |
| `docs/architecture/shader-elixir-interface.md` | 本設計への参照を追加 |

---

## 5. 将来のサンドボックス化との関係

不信頼コンテンツ（ユーザーアップロード、外部プラグイン等）を利用する場合:

- アセット読み込みは**専用のサンドボックスディレクトリ**内に制限する
- `canonicalize` + ベースディレクトリ検証は必須
- 必要に応じて、読み込み可能なファイル拡張子を `.wgsl`, `.png` 等に制限する

本設計の Phase 2 までを実装しておくことで、将来的なサンドボックス化の土台となる。

---

## 6. 参考

- [CWE-22: Improper Limitation of a Pathname to a Restricted Directory](https://cwe.mitre.org/data/definitions/22.html)
- [std::fs::canonicalize - Rust](https://doc.rust-lang.org/std/fs/fn.canonicalize.html)
- [shader-elixir-interface.md](shader-elixir-interface.md) — パス導出ロジック
