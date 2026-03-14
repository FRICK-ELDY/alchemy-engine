# Contents 共有コンポーネント再配置 実施手順書

> 作成日: 2026-03-10  
> 目的: 共有コンポーネントを `Contents.Components.*` 以下に再配置し、
> 将来的に個々の content が共有コンポーネントの組み合わせで構成される設計にする。

---

## 1. 目標構成

### 1.1 設計方針

- **Uncategorized**: コンポーネントの種別（未分類）。Registry / Telemetry / Menu を格納。
- **Nodes.Users**: ノードの塊としてのコンポーネント種別。LocalUser を格納。

### 1.2 ディレクトリ構造（移行後）

```
apps/contents/lib/contents/
  components/
    uncategorized/           # 種別: Uncategorized
      registry.ex            # Contents.Components.Uncategorized.Registry
      telemetry.ex           # Contents.Components.Uncategorized.Telemetry
      menu.ex                # Contents.Components.Uncategorized.Menu
    nodes/
      users/
        local_user.ex        # Contents.Components.Nodes.Users.LocalUser
```

### 1.3 モジュール対応

| 移行元 | 移行先 |
|:---|:---|
| `Contents.LocalUserComponent` | `Contents.Components.Nodes.Users.LocalUser` |
| `Contents.TelemetryComponent` | `Contents.Components.Uncategorized.Telemetry` |
| `Contents.MenuComponent` | `Contents.Components.Uncategorized.Menu` |
| `Content.ComponentRegistry` | `Contents.Components.Uncategorized.Registry` |

### 1.4 注意事項

- `Content.VampireSurvivor.LocalUserComponent` はコンテンツ専用オーバーライドのため **移動しない**
- `local_user_input_module/0` のデフォルト返却値を `Contents.Components.Nodes.Users.LocalUser` に変更する

---

## 2. 実施手順

### Phase 1: 新ファイルの作成と移動

#### Step 1-1: ディレクトリ作成

```bash
mkdir -p apps/contents/lib/contents/components/uncategorized
mkdir -p apps/contents/lib/contents/components/nodes/users
```

#### Step 1-2: LocalUser の移動（nodes/users に配置）

1. `apps/contents/lib/contents/local_user_component.ex` の内容をコピー
2. 新規作成: `apps/contents/lib/contents/components/nodes/users/local_user.ex`
3. モジュール名を `Contents.Components.Nodes.Users.LocalUser` に変更
4. `@moduledoc` の `LocalUserComponent` 表記を `LocalUser` に更新（任意）
5. 旧ファイル `local_user_component.ex` を削除

#### Step 1-3: Registry の移動（uncategorized に配置）

1. `apps/contents/lib/contents/component_registry.ex` の内容をコピー
2. 新規作成: `apps/contents/lib/contents/components/uncategorized/registry.ex`
3. モジュール名を `Contents.Components.Uncategorized.Registry` に変更
4. 旧ファイル `component_registry.ex` を削除

#### Step 1-4: Telemetry の移動（uncategorized に配置）

1. `apps/contents/lib/contents/telemetry_component.ex` の内容をコピー
2. 新規作成: `apps/contents/lib/contents/components/uncategorized/telemetry.ex`
3. モジュール名を `Contents.Components.Uncategorized.Telemetry` に変更
4. `get_input_state/1` 内の `Contents.ComponentList.local_user_input_module()` 呼び出しはそのまま（ComponentList は後で更新）
5. 旧ファイル `telemetry_component.ex` を削除

#### Step 1-5: Menu の移動（uncategorized に配置）

1. `apps/contents/lib/contents/menu_component.ex` の内容をコピー
2. 新規作成: `apps/contents/lib/contents/components/uncategorized/menu.ex`
3. モジュール名を `Contents.Components.Uncategorized.Menu` に変更
4. `get_menu_ui/2` 内の参照は **まだ更新しない**（Step 2 で一括）
5. 旧ファイル `menu_component.ex` を削除

---

### Phase 2: 参照の更新

#### Step 2-1: ComponentList の更新

**ファイル:** `apps/contents/lib/contents/component_list.ex`

| 箇所 | 変更前 | 変更後 |
|:---|:---|:---|
| moduledoc の LocalUserComponent | `Contents.LocalUserComponent` | `Contents.Components.Nodes.Users.LocalUser` |
| moduledoc の TelemetryComponent | `Contents.TelemetryComponent` | `Contents.Components.Uncategorized.Telemetry` |
| ensure_contains(Telemetry) | `Contents.TelemetryComponent` | `Contents.Components.Uncategorized.Telemetry` |
| local_user_input_module のデフォルト | `Contents.LocalUserComponent` | `Contents.Components.Nodes.Users.LocalUser` |

#### Step 2-2: ContentBehaviour の更新

**ファイル:** `apps/core/lib/core/content_behaviour.ex`

| 箇所 | 変更前 | 変更後 |
|:---|:---|:---|
| local_user_input_module の doc | `Contents.LocalUserComponent` | `Contents.Components.Nodes.Users.LocalUser` |

#### Step 2-3: GameEvents の更新

**ファイル:** `apps/contents/lib/contents/game_events.ex`

| 箇所 | 変更前 | 変更後 |
|:---|:---|:---|
| get_move_vector のフォールバック | `Contents.LocalUserComponent` | `Contents.Components.Nodes.Users.LocalUser` |
| コメント「LocalUserComponent」 | （任意）`Contents.Components.Nodes.Users.LocalUser` に統一 |

#### Step 2-4: Menu の内部参照更新

**ファイル:** `apps/contents/lib/contents/components/uncategorized/menu.ex`

| 箇所 | 変更前 | 変更後 |
|:---|:---|:---|
| get_menu_ui/2 内 | `Contents.TelemetryComponent.get_input_state(room_id)` | `Contents.Components.Uncategorized.Telemetry.get_input_state(room_id)` |
| get_menu_ui/2 内 | `Contents.LocalUserComponent.get_client_info(room_id)` | `Contents.Components.Nodes.Users.LocalUser.get_client_info(room_id)` |
| moduledoc の TelemetryComponent | （任意）新モジュール名に合わせる | |

#### Step 2-5: Telemetry.RenderComponent の更新

**ファイル:** `apps/contents/lib/contents/telemetry/render_component.ex`

| 箇所 | 変更前 | 変更後 |
|:---|:---|:---|
| get_menu_visible / get_menu_ui | `Contents.MenuComponent` | `Contents.Components.Uncategorized.Menu` |
| moduledoc の MenuComponent | （任意）新モジュール名に合わせる | |

#### Step 2-6: Telemetry content の更新

**ファイル:** `apps/contents/lib/contents/telemetry.ex`

| 箇所 | 変更前 | 変更後 |
|:---|:---|:---|
| components/0 内 | `Contents.MenuComponent` | `Contents.Components.Uncategorized.Menu` |

#### Step 2-7: テストの更新

**ファイル:** `apps/contents/test/content/component_list_test.exs`

| 箇所 | 変更前 | 変更後 |
|:---|:---|:---|
| 期待値（未実装時） | `Contents.LocalUserComponent` | `Contents.Components.Nodes.Users.LocalUser` |
| 期待値（nil 時） | `Contents.LocalUserComponent` | `Contents.Components.Nodes.Users.LocalUser` |
| テスト説明文 | LocalUserComponent | LocalUser（任意） |

**注意:** `Content.VampireSurvivor.LocalUserComponent` を返すテストは変更しない（content のオーバーライドテスト）。

---

### Phase 3: ドキュメントの更新（任意）

以下のファイルで旧モジュール名が言及されている場合、必要に応じて更新する。

| ファイル | 更新内容 |
|:---|:---|
| `docs/plan/completed/platform-info-crate-and-local-user-execution-plan.md` | モジュール名を新表記に |
| `docs/plan/reference/improvement-plan.md` | モジュール名を新表記に |
| `docs/architecture/elixir/contents.md` | コンポーネント一覧を新構成に |
| `docs/architecture/overview.md` | component_list の説明を新モジュール名に |

---

## 3. 変更ファイル一覧（チェックリスト）

### 新規作成

- [ ] `apps/contents/lib/contents/components/nodes/users/local_user.ex`
- [ ] `apps/contents/lib/contents/components/uncategorized/registry.ex`
- [ ] `apps/contents/lib/contents/components/uncategorized/telemetry.ex`
- [ ] `apps/contents/lib/contents/components/uncategorized/menu.ex`

### 削除

- [ ] `apps/contents/lib/contents/local_user_component.ex`
- [ ] `apps/contents/lib/contents/component_registry.ex`
- [ ] `apps/contents/lib/contents/telemetry_component.ex`
- [ ] `apps/contents/lib/contents/menu_component.ex`

### 参照更新

- [ ] `apps/contents/lib/contents/component_list.ex`
- [ ] `apps/core/lib/core/content_behaviour.ex`
- [ ] `apps/contents/lib/contents/game_events.ex`
- [ ] `apps/contents/lib/contents/components/uncategorized/menu.ex`（内部参照）
- [ ] `apps/contents/lib/contents/telemetry/render_component.ex`
- [ ] `apps/contents/lib/contents/telemetry.ex`
- [ ] `apps/contents/test/content/component_list_test.exs`

---

## 4. 検証手順

1. **コンパイル**
   ```bash
   mix compile --warnings-as-errors
   ```

2. **テスト**
   ```bash
   mix test apps/contents/test/content/component_list_test.exs
   mix test apps/contents/test/content/local_user_component_test.exs
   ```

3. **動作確認**
   - `config :server, :current` で VampireSurvivor / AsteroidArena / Telemetry のいずれかを選択し起動
   - メニュー表示・ESC トグル・入力状態表示が問題なく動作することを確認

---

## 5. ロールバック

問題発生時は以下で復元可能。

1. 新規作成した `components/` 以下を削除
2. 旧ファイル（`local_user_component.ex` 等）を git から復元
3. Phase 2 で変更した参照を元に戻す

```bash
git checkout -- apps/contents/lib/contents/local_user_component.ex
git checkout -- apps/contents/lib/contents/component_registry.ex
# ... 他も同様
```

---

## 6. 将来の拡張

- `Contents.Components.Uncategorized`（コンポーネント種別）内が役割別に整理できたタイミングで、`Contents.Components.Rendering.Menu` 等の新種別へ分割可能
- `Content.ComponentRegistry` を参照している箇所があれば、`Contents.Components.Uncategorized.Registry` に統一する
