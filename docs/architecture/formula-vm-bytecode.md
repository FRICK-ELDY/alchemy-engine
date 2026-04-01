# Formula VM バイトコード仕様（P1-3）

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) P1-3  
> 目的: Elixir が生成するバイトコード定義の形式を仕様として文書化する

---

## 1. 概要

Formula VM は **レジスタマシン** 形式のスタックレス VM である。Elixir 側で `Core.FormulaGraph` または `Core.Formula.build/1` によりバイトコードを生成し、Rust の NIF `run_formula_bytecode` で実行する。

**責務の分担**:
- **Elixir (contents)**: バイトコードの**定義**（生成）
- **Rust (nif)**: バイトコードの**実行**（解釈）

---

## 2. 値型

| 型 | Rust 表現 | 説明 |
|:---|:---|:---|
| F32 | `f32` | 32bit 浮動小数 |
| I32 | `i32` | 32bit 符号付き整数 |
| Bool | `bool` | 真偽値 |

演算時の型変換:
- I32 同士の四則演算 → I32（saturating 演算）
- それ以外の数値演算 → F32 に変換して演算
- 比較 (lt, gt, eq) → 両オペランドを F32 として比較（Eq は Bool 同士・I32 同士も対応）

---

## 3. レジスタ

- **本数**: 64 (`REGISTER_COUNT`)
- **型**: 各レジスタは `Option<Value>`。未初期化参照時はエラー。
- **番号**: u8 (0..63)

---

## 4. OpCode 一覧

バイトコードは **可変長**。各命令は `[opcode_byte, ...operands]` の形式。

### 4.1 LoadInput (0)

入力マップから値を読み、レジスタに格納。

| バイト | 内容 |
|:---|:---|
| 0 | OpCode (0) |
| 1 | dst (レジスタ番号) |
| 2 | name_len (名前のバイト数) |
| 3..2+name_len | name_bytes (UTF-8) |

**制約**: name_len ≤ 255

---

### 4.2 LoadI32 (1)

定数 i32 をレジスタへ。

| バイト | 内容 |
|:---|:---|
| 0 | OpCode (1) |
| 1 | dst |
| 2..5 | value (i32, little-endian) |

---

### 4.3 LoadF32 (2)

定数 f32 をレジスタへ。

| バイト | 内容 |
|:---|:---|
| 0 | OpCode (2) |
| 1 | dst |
| 2..5 | value (f32, little-endian) |

---

### 4.4 LoadBool (3)

定数 bool をレジスタへ。

| バイト | 内容 |
|:---|:---|
| 0 | OpCode (3) |
| 1 | dst |
| 2 | value (0=false, 非0=true) |

---

### 4.5 二項演算 (4..10)

`Add`, `Sub`, `Mul`, `Div`, `Lt`, `Gt`, `Eq`

| バイト | 内容 |
|:---|:---|
| 0 | OpCode (4..10) |
| 1 | dst |
| 2 | src_a |
| 3 | src_b |

| OpCode | 値 | 意味 |
|:---|:---|:---|
| Add | 4 | r_dst = r_a + r_b |
| Sub | 5 | r_dst = r_a - r_b |
| Mul | 6 | r_dst = r_a * r_b |
| Div | 7 | r_dst = r_a / r_b（ゼロ除算でエラー） |
| Lt | 8 | r_dst = (r_a < r_b) |
| Gt | 9 | r_dst = (r_a > r_b) |
| Eq | 10 | r_dst = (r_a == r_b) |

---

### 4.6 StoreOutput (11)

レジスタ値を出力リストに追加。

| バイト | 内容 |
|:---|:---|
| 0 | OpCode (11) |
| 1 | src |

---

### 4.7 ReadStore (12)

Store からキーで値を読み、レジスタへ。

| バイト | 内容 |
|:---|:---|
| 0 | OpCode (12) |
| 1 | dst |
| 2 | key_len |
| 3..2+key_len | key_bytes (UTF-8) |

キーが存在しない場合はエラー。

---

### 4.8 WriteStore (13)

レジスタ値を Store に書き込む。

| バイト | 内容 |
|:---|:---|
| 0 | OpCode (13) |
| 1 | src |
| 2 | key_len |
| 3..2+key_len | key_bytes (UTF-8) |

---

## 5. 実行モデル

```
入力: bytecode, inputs (Map), store_values (Map)

1. バイトコードを先頭から順にデコード → Instruction 列
2. レジスタ配列を初期化（全 None）
3. 各命令を順に実行
4. StoreOutput のたびに outputs に値を追加
5. ReadStore/WriteStore で store を更新
6. 終了後: (outputs, store) を返す
```

- **入力 (inputs)**: 実行開始時に渡す名前→値のマップ。LoadInput で参照。
- **Store**: 永続状態。実行開始時の store_values を初期値とし、WriteStore で更新。永続化は Elixir の責務。
- **出力 (outputs)**: StoreOutput で追加された値のリスト。順序は StoreOutput の出現順。

---

## 6. エラー

| エラー | 条件 |
|:---|:---|
| DecodeError::UnexpectedEof | オペランド不足 |
| DecodeError::InvalidOpCode | 未定義の OpCode |
| DecodeError::RegisterOutOfRange | レジスタ番号 ≥ 64 |
| DecodeError::InvalidUtf8 | 名前/キーが不正 UTF-8 |
| VmError::InputNotFound | LoadInput の名前が inputs にない |
| VmError::StoreNotFound | ReadStore のキーが store にない |
| VmError::TypeMismatch | 演算型が不適合 |
| VmError::DivisionByZero | ゼロ除算 |

---

## 7. Elixir での生成

### 7.1 命令形式（Formula.build/1 の入力）

```elixir
# 命令はタプルのリスト
[
  {:load_input, dst, "name"},
  {:load_i32, dst, value},
  {:load_f32, dst, value},
  {:load_bool, dst, true},
  {:add, dst, src_a, src_b},
  {:sub, dst, src_a, src_b},
  {:mul, dst, src_a, src_b},
  {:div, dst, src_a, src_b},
  {:lt, dst, src_a, src_b},
  {:gt, dst, src_a, src_b},
  {:eq, dst, src_a, src_b},
  {:store_output, src},
  {:read_store, dst, "key"},
  {:write_store, src, "key"}
]
```

### 7.2 FormulaGraph からのコンパイル

`Core.FormulaGraph.compile/1` がグラフをトポロジカルソートし、ノードを命令列に変換。`Formula.build/1` でバイナリ化。

ノード種別と命令の対応:
- `:input` → LoadInput
- `:int` → LoadI32
- `:float` → LoadF32
- `:bool` → LoadBool
- `:add`..`:eq` → 対応する二項演算
- `:output` → StoreOutput
- `:read_store` → ReadStore
- `:write_store` → WriteStore

---

## 8. 実装ファイル参照

| レイヤー | ファイル |
|:---|:---|
| OpCode 定義 | `rust/nif/src/formula/opcode.rs` |
| デコード | `rust/nif/src/formula/decode.rs` |
| VM 実行 | `rust/nif/src/formula/vm.rs` |
| 値型 | `rust/nif/src/formula/value.rs` |
| Elixir 生成 | `apps/core/lib/core/formula.ex` |
| グラフ→バイトコード | `apps/core/lib/core/formula_graph.ex` |

---

## 9. 関連ドキュメント

- [formula-hardcode-inventory.md](../../workspace/2_todo/formula-hardcode-inventory.md) — ハードコード一覧（P1-1）
- [formula-migration-evaluation.md](../../workspace/2_todo/formula-migration-evaluation.md) — 武器式の Formula 移行評価（P1-2）
- [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) — 方針・リファクタリング計画
