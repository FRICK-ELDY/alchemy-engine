# Types プリミティブ型モジュール 実施手順書

> 作成日: 2026-03-10  
> 目的: `Types` 以下にプリミティブ型モジュールを作成し、コンテンツ制作の土台とする。
>
> 設計前提（階層）:
> - Content = コンポーネントの塊
> - Component = ノードの塊
> - Node = (Input, Output, Connection, Parameter) の塊
> - Parameter = (Key, Type, Value) の塊

---

## 1. 目標構成

### 1.1 lib 直下のディレクトリ構造

```
apps/contents/lib/
  contents/
  components/
  nodes/
  types/              # プリミティブ型（parameters を統合）
    int.ex            # Types.Int
    int2.ex           # Types.Int2
    int3.ex           # Types.Int3
    float.ex          # Types.Float
    float2.ex         # Types.Float2
    float3.ex         # Types.Float3
    string.ex         # Types.String
```

### 1.2 モジュール一覧

| ファイル | モジュール名 | 型の意味 |
|:---|:---|:---|
| int.ex | `Types.Int` | 整数 (integer) |
| int2.ex | `Types.Int2` | 2要素整数 (x, y) |
| int3.ex | `Types.Int3` | 3要素整数 (x, y, z) |
| float.ex | `Types.Float` | 浮動小数 |
| float2.ex | `Types.Float2` | 2要素浮動小数 (x, y) |
| float3.ex | `Types.Float3` | 3要素浮動小数 (x, y, z) |
| string.ex | `Types.String` | 文字列 |

### 1.3 モジュールの責務（想定）

各型モジュールは以下を提供する（Phase 1 では最小限）:

- `@type t` または `@type value` : 値の型 spec
- `@doc` : 型の説明
- （将来）`default/0` : デフォルト値
- （将来）`validate/1` : 値の検証

---

## 2. 実施手順

### Phase 1: ディレクトリ・ファイル作成

#### Step 1-1: ディレクトリ作成

```bash
mkdir -p apps/contents/lib/types
```

#### Step 1-2: Int モジュール作成

**ファイル:** `apps/contents/lib/types/int.ex`

```elixir
defmodule Types.Int do
  @moduledoc """
  パラメータ型: 整数 (integer)。
  Parameter = (Key, Type, Value) の Type として使用する。
  """
  @type t :: integer()
end
```

#### Step 1-3: Int2 モジュール作成

**ファイル:** `apps/contents/lib/types/int2.ex`

```elixir
defmodule Types.Int2 do
  @moduledoc """
  パラメータ型: 2要素整数 (x, y)。
  Parameter = (Key, Type, Value) の Type として使用する。
  """
  @type t :: {integer(), integer()}
end
```

#### Step 1-4: Int3 モジュール作成

**ファイル:** `apps/contents/lib/types/int3.ex`

```elixir
defmodule Types.Int3 do
  @moduledoc """
  パラメータ型: 3要素整数 (x, y, z)。
  Parameter = (Key, Type, Value) の Type として使用する。
  """
  @type t :: {integer(), integer(), integer()}
end
```

#### Step 1-5: Float モジュール作成

**ファイル:** `apps/contents/lib/types/float.ex`

```elixir
defmodule Types.Float do
  @moduledoc """
  パラメータ型: 浮動小数。
  Parameter = (Key, Type, Value) の Type として使用する。
  """
  @type t :: float()
end
```

#### Step 1-6: Float2 モジュール作成

**ファイル:** `apps/contents/lib/types/float2.ex`

```elixir
defmodule Types.Float2 do
  @moduledoc """
  パラメータ型: 2要素浮動小数 (x, y)。
  Parameter = (Key, Type, Value) の Type として使用する。
  """
  @type t :: {float(), float()}
end
```

#### Step 1-7: Float3 モジュール作成

**ファイル:** `apps/contents/lib/types/float3.ex`

```elixir
defmodule Types.Float3 do
  @moduledoc """
  パラメータ型: 3要素浮動小数 (x, y, z)。
  Parameter = (Key, Type, Value) の Type として使用する。
  """
  @type t :: {float(), float(), float()}
end
```

#### Step 1-8: String モジュール作成

**ファイル:** `apps/contents/lib/types/string.ex`

```elixir
defmodule Types.String do
  @moduledoc """
  パラメータ型: 文字列。
  Parameter = (Key, Type, Value) の Type として使用する。
  """
  @type t :: String.t()
end
```

---

## 3. 変更ファイル一覧（チェックリスト）

### 新規作成

- [ ] `apps/contents/lib/types/int.ex`
- [ ] `apps/contents/lib/types/int2.ex`
- [ ] `apps/contents/lib/types/int3.ex`
- [ ] `apps/contents/lib/types/float.ex`
- [ ] `apps/contents/lib/types/float2.ex`
- [ ] `apps/contents/lib/types/float3.ex`
- [ ] `apps/contents/lib/types/string.ex`

---

## 4. 検証手順

1. **コンパイル**
   ```bash
   mix compile --warnings-as-errors
   ```

2. **型の参照確認（IEx）**
   ```elixir
   alias Types.Int
   alias Types.Float2
   # 型が正しく解決されることを確認
   ```

---

## 5. 注意事項

- Elixir 標準の `String` モジュールと名前が衝突する可能性あり。`Types.String` を参照する場合は `Types.String` と完全修飾するか、コンテキストで曖昧でないことを確認すること。
- `apps/contents/lib/` 直下に `types/` を置くため、contents アプリのコンパイル対象に含まれる（Mix の `elixirc_paths` がデフォルト `["lib"]` の場合）。

---

## 6. 将来の拡張

- `default/0`, `validate/1` の追加
- `ref<T>` 形式の参照型（例: `Types.Ref`）の追加
- Rust との型マッピング定義
- ネットワーク符号化時の型タグ定義
