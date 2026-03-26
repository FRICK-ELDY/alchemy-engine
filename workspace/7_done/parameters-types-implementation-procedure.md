# Types プリミティブ型モジュール 実施手順書（実施済み）

> 作成日: 2026-03-10  
> 完了日: 2026-03-15  
> 参照: [fix-contents-implementation-procedure.md](./fix-contents-implementation-procedure.md)  
> 目的: `Types` 以下にプリミティブ型モジュールを作成し、コンテンツ制作の土台とする。
>
> **実施結果**: 設計変更により `types` → `structs` に統合。プリミティブ型は `Structs.Category.Value.*` および `Structs.Category.Text.*` として [fix_contents アーキテクチャ](../../architecture/fix_contents.md) 内で実装済み。
>
> 設計前提（階層）:
> - Content = コンポーネントの塊
> - Component = ノードの塊
> - Node = (Input, Output, Connection, Parameter) の塊
> - Parameter = (Key, Type, Value) の塊

---

## 1. 目標構成（当初案）

### 1.1 lib 直下のディレクトリ構造（当初）

```
apps/contents/lib/
  contents/
  components/
  nodes/
  types/              # プリミティブ型（parameters を統合）→ structs に変更
    int.ex            # Types.Int
    int2.ex           # Types.Int2
    int3.ex           # Types.Int3
    float.ex          # Types.Float
    float2.ex         # Types.Float2
    float3.ex         # Types.Float3
    string.ex         # Types.String
```

### 1.2 モジュール対応（types → structs）

| 当初 | 実装先 |
|:---|:---|
| `Types.Int` (t, t2, t3) | `Structs.Category.Value.Int` (t, t2, t3, t4) |
| `Types.Float` (t, t2, t3) | `Structs.Category.Value.Float` (t, t2, t3, t4, 行列, quaternion) |
| `Types.String` | `Structs.Category.Text.String` |

### 1.3 モジュールの責務（想定）

各型モジュールは以下を提供する（Phase 1 では最小限）:

- `@type t` または `@type value` : 値の型 spec
- `@doc` : 型の説明
- （将来）`default/0` : デフォルト値
- （将来）`validate/1` : 値の検証

---

## 2. 実施手順（当初案・参考）

> 以下は当初の types 案。実際の実装は structs として fix_contents 実施手順書に従い実施済み。

### Phase 1: ディレクトリ・ファイル作成

#### Step 1-1: ディレクトリ作成

```bash
mkdir -p apps/contents/lib/types
```

#### Step 1-2〜1-8: モジュール作成

（省略。実装は `apps/contents/lib/structs/category/value/` および `structs/category/text/` を参照）

---

## 3. 変更ファイル一覧（実施済み・structs として）

- [x] `apps/contents/lib/structs/category/value/int.ex` — `Structs.Category.Value.Int`
- [x] `apps/contents/lib/structs/category/value/float.ex` — `Structs.Category.Value.Float`
- [x] `apps/contents/lib/structs/category/text/string.ex` — `Structs.Category.Text.String`
- （上記に加え、Byte, UShort, UInt, ULong, SByte, Short, Long, Decimal, Color, Char, DateTime, TimeSpan, Guid 等も structs に含まれる）

---

## 4. 検証手順

1. **コンパイル**
   ```bash
   mix compile --warnings-as-errors
   ```

2. **型の参照確認（IEx）**
   ```elixir
   alias Structs.Category.Value.Int
   alias Structs.Category.Value.Float
   alias Structs.Category.Text.String
   # 型が正しく解決されることを確認
   ```

---

## 5. 注意事項

- Elixir 標準の `String` モジュールと名前が衝突する可能性あり。`Structs.Category.Text.String` を参照する場合は完全修飾するか、コンテキストで曖昧でないことを確認すること。
- structs は fix_contents アーキテクチャの基盤層として contents アプリのコンパイル対象に含まれる。

---

## 6. 将来の拡張

- `default/0`, `validate/1` の追加
- `ref<T>` 形式の参照型（例: `Types.Ref`）の追加
- Rust との型マッピング定義
- ネットワーク符号化時の型タグ定義
