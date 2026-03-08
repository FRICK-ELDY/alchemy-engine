# AlchemyEngine ランチャー設計

> 作成日: 2026-03-07  
> 実装日: 2026-03-08  
> 目的: システムトレイから zenohd / HL-Server / クライアントを管理し、play.bat / play.sh に代わるユーザー体験を提供する。

## 実装状況

- **launcher** クレート: `native/launcher/`
- 起動: `bin/launcher.bat` (Windows) / `bin/launcher.sh` (Linux/macOS)

---

## 現状起こっている問題（2026-03-08 時点）

実装済み機能が多く、動くことを段階的に確認せずに進めた結果、次の問題が発生している。

| # | 問題 | 内容 | 影響 |
|:---|:---|:---|:---|
| 1 | **ポート確認の誤検知** | zenohd は実際に起動・待ち受けしているのに、「zenohd が 10 秒以内に起動しませんでした」と表示される | zenohd Run が失敗扱いになり、ユーザーが誤認する |
| 2 | **一気に作りすぎた** | トレイ・メニュー・zenohd・HL-Server・Client・アイコン・非同期化・メニュー再構築をまとめて実装 | 問題の切り分けが難しく、どこで壊れているか特定しづらい |
| 3 | **動くことの検証不足** | 各フェーズごとに「起動する」「操作できる」を確認せずに次へ進んだ | 土台が固まる前に上に積み重ねてしまった |
| 4 | **zenohd 起動方式の本番不適** | Windows で `bin/start_zenohd.bat` 経由でしか安定起動できない | 本番環境ではバッチに依存せず直接起動したい（既存の課題セクション参照） |
| 5 | **メニュー状態の更新** | `set_enabled` がトレイ表示に反映されない問題があり、メニュー再構築で回避した | tray-icon のメニュー参照の扱いを理解しきれていない |

**方針**: 変更を一度なかったことにし、フェーズ 0 から「動くこと」を確認しながら組み立て直す。  
実施計画は [launcher-design_do.md](./launcher-design_do.md) を参照。

---

## 1. 背景・課題

### 1.1 現状の問題

| 課題 | 内容 |
|:---|:---|
| 固定待機 | play.bat はポート確認を行うが、起動完了の可視化がない |
| プロセス管理 | zenohd / mix run が残り続け、ユーザーが気づきにくい |
| ログ参照 | コンソール出力を確認しづらい |
| 更新・謝辞 | 専用 UI がなく、手動で確認するしかない |

### 1.2 目標

- **Discord 風トレイインジケーター**: トレイアイコン右クリックでメニューを開き、各サービスを管理
- **起動確認の UX 改善**: ポート確認で待機時間を最小化
- **play.bat / play.sh の廃止**: ランチャー exe に一本化

---

## 2. UI 仕様

### 2.1 メニュー構造（トレイ右クリック）

```
AlchemyEngine
-----------------------
Check for Update...
acknowledgements
-----------------------
zenohd About
zenohd Run
zenohd Command
zenohd Quit
-----------------------
HL-Server About
HL-Server Run
HL-Server Command
HL-Server Quit
-----------------------
Client Run
```

### 2.2 各項目の動作

| 項目 | 動作 |
|:---|:---|
| **AlchemyEngine** | タイトル行（非クリック） |
| **Check for Update...** | アップデート確認ダイアログを開く |
| **acknowledgements** | 謝辞・ライセンス一覧を開く |
| **zenohd About** | zenohd のバージョン・役割説明を表示 |
| **zenohd Run** | zenohd を起動（ポート 7447 で待ち受けを確認） |
| **zenohd Command** | zenohd のコンソール出力ウィンドウを表示 |
| **zenohd Quit** | zenohd を終了 |
| **HL-Server About** | Elixir サーバー（mix run）の説明を表示 |
| **HL-Server Run** | mix run を起動（ポート 4000 で待ち受けを確認） |
| **HL-Server Command** | mix run のコンソール出力ウィンドウを表示 |
| **HL-Server Quit** | mix run を終了 |
| **Client Run** | zenohd と HL-Server の起動を確認してから desktop_client を起動 |

### 2.3 状態表示

- **zenohd Run / zenohd Quit**: 起動中は「zenohd Quit」を有効化し、「zenohd Run」を無効化
- **HL-Server Run / HL-Server Quit**: 同様
- **Client Run**: zenohd と HL-Server が両方起動していない場合は無効化、または押下時に起動を待ってから起動

### 2.4 トレイアイコン

- 通常: AlchemyEngine ロゴ or 既定アイコン
- zenohd 起動中: アイコン変更 or バッジ（任意）
- HL-Server 起動中: 同上（任意）
- 両方起動: 準備完了を表す状態（任意）

---

## 3. アーキテクチャ

### 3.1 全体構成

```mermaid
flowchart TB
    subgraph Tray["トレイアプリ (launcher)"]
        UI[メニュー UI]
        ZenohdMgr[zenohd Manager]
        HLSvrMgr[HL-Server Manager]
        ClientMgr[Client Launcher]
        Update[Update Checker]
        Ack[Acknowledgements]
    end
    
    subgraph Ext["外部プロセス"]
        Zenohd[zenohd]
        MixRun[mix run]
        Client[desktop_client]
    end
    
    UI --> ZenohdMgr
    UI --> HLSvrMgr
    UI --> ClientMgr
    UI --> Update
    UI --> Ack
    
    ZenohdMgr -->|spawn/kill| Zenohd
    HLSvrMgr -->|spawn/kill| MixRun
    ClientMgr -->|spawn| Client
    
    ZenohdMgr -.->|port 7447| Zenohd
    HLSvrMgr -.->|port 4000| MixRun
    ClientMgr -.->|起動確認後に spawn| Client
```

### 3.2 コンポーネント責務

| コンポーネント | 責務 |
|:---|:---|
| **zenohd Manager** | zenohd の起動・終了・ポート確認（7447）、コンソール出力バッファ |
| **HL-Server Manager** | mix run の起動・終了・ポート確認（4000）、コンソール出力バッファ |
| **Client Launcher** | zenohd と HL-Server のポート確認後、desktop_client を spawn |
| **Update Checker** | リリース一覧の取得・比較、ダイアログ表示 |
| **Acknowledgements** | 謝辞テキストの表示 |

---

## 4. 技術選定

### 4.1 トレイ UI

| 選択肢 | メリット | デメリット |
|:---|:---|:---|
| **tray-icon + tao** | 軽量、クロスプラットフォーム、Rust ネイティブ | メニュー構築は自前 |
| **tray-item** | シンプル | メンテナンス状況要確認 |
| **tao** (単体) | ウィンドウ非表示でトレイのみ可能 | トレイ専用は少し工夫が必要 |

**案**: `tray-icon` クレート（tao ベース）を使用。メニュー項目の追加・有効/無効切り替えに対応。

### 4.2 プロセス管理

- `std::process::Command` で zenohd / mix run / desktop_client を起動
- 子プロセス PID を保持し、Quit 時に `kill` または `TerminateProcess`（Windows）
- コンソール出力: `Command::stdout(Stdio::piped)` でパイプし、バッファに蓄積。Command ウィンドウで表示

### 4.3 ポート確認

- `std::net::TcpStream::connect_timeout` で 127.0.0.1:7447 / 127.0.0.1:4000 に接続試行
- ポーリング間隔 1 秒、最大待機 60 秒程度

### 4.4 配置

- 新規クレート: `native/launcher/`
- ワークスペースに追加し、`cargo build -p launcher` でビルド
- 出力 exe: `launcher.exe`（リリース時）

---

## 5. 実装フェーズ

| フェーズ | 内容 | 工数目安 |
|:---|:---|:---|
| 1 | トレイアプリ骨格、メニュー表示、Quit（アプリ終了） | 1 週間 |
| 2 | zenohd Run / Quit / Command、ポート確認 | 1 週間 |
| 3 | HL-Server Run / Quit / Command、ポート確認 | 1 週間 |
| 4 | Client Run（両方起動確認後に起動） | 数日 |
| 5 | Check for Update、acknowledgements | 1 週間（任意） |
| 6 | play.bat / play.sh 廃止、README 更新 | 数日 |

---

## 6. パス・設定

### 6.1 前提

- ランチャー exe はプロジェクトルート付近に配置、または `--root` で指定
- zenohd: `PATH` 上の `zenohd`（`cargo install eclipse-zenoh`）
- mix run: `ROOT` で `mix run --no-halt`
- desktop_client: `ROOT/native/target/release/desktop_client.exe`（未ビルド時は `cargo run -p desktop_client`）

### 6.2 設定ファイル（任意）

- `config/launcher.toml` などで以下を上書き可能に:
  - zenohd パス
  - mix run の作業ディレクトリ
  - desktop_client パス
  - 接続先（`tcp/127.0.0.1:7447` 等）
  - ルーム ID

---

## 7. play.bat / play.sh の扱い

- ランチャー実装完了後、`play.bat` と `play.sh` を**非推奨**とする
- README の起動手順を「launcher を起動し、zenohd Run → HL-Server Run → Client Run」に変更
- 開発者向けに「手動起動」手順（zenohd / mix run / cargo run を別ターミナルで実行）を残す

---

## 8. 処理シーケンス図

各処理単位の Mermaid シーケンス図です。

### 8.1 起動シーケンス

```mermaid
sequenceDiagram
    participant User as ユーザー
    participant Main as main
    participant Tao as tao EventLoop
    participant TrayIcon as TrayIconEvent
    participant MenuEvent as MenuEvent
    participant ZenohdMgr as ZenohdManager
    participant HlSvrMgr as HlServerManager
    participant Menu as メニュー

    User->>Main: launcher.exe 起動
    Main->>Main: env_logger 初期化
    Main->>Tao: EventLoopBuilder::with_user_event()
    Main->>Tao: build()
    Main->>TrayIcon: set_event_handler(proxy)
    Main->>MenuEvent: set_event_handler(proxy)
    Main->>ZenohdMgr: new()
    Main->>HlSvrMgr: new()
    Main->>Menu: build_menu()
    Main->>Main: create_tray_icon()
    Main->>Tao: run(event_handler)
    Note over Tao: イベントループ開始
```

### 8.2 メニューイベント処理シーケンス

```mermaid
sequenceDiagram
    participant User as ユーザー
    participant Tray as トレイ
    participant MenuEvent as MenuEvent
    participant Tao as EventLoop
    participant Handler as handle_menu_event
    participant ZenohdMgr as ZenohdManager
    participant HlSvrMgr as HlServerManager
    participant Client as ClientLauncher
    participant MenuItems as MenuItems

    User->>Tray: 右クリック
    Tray->>Tray: メニュー表示
    User->>Tray: メニュー項目クリック
    Tray->>MenuEvent: 発火
    MenuEvent->>Tao: send_event(MenuEvent)
    Tao->>Handler: UserEvent(MenuEvent)
    Handler->>Handler: event.id() で分岐

    alt zenohd_run
        Handler->>ZenohdMgr: run()
        ZenohdMgr-->>Handler: Ok/Err
        Handler->>MenuItems: set_enabled(zenohd_run/quit)
    else zenohd_quit
        Handler->>ZenohdMgr: quit()
        Handler->>MenuItems: set_enabled(zenohd_run/quit)
    else hl_server_run
        Handler->>HlSvrMgr: run()
        HlSvrMgr-->>Handler: Ok/Err
        Handler->>MenuItems: set_enabled(hl_server_run/quit)
    else hl_server_quit
        Handler->>HlSvrMgr: quit()
        Handler->>MenuItems: set_enabled(hl_server_run/quit)
    else client_run
        Handler->>Client: run_client()
    else quit
        Handler-->>Tao: return true (ControlFlow::Exit)
    end
```

### 8.3 zenohd Run シーケンス

```mermaid
sequenceDiagram
    participant Handler as handle_menu_event
    participant ZenohdMgr as ZenohdManager
    participant PortCheck as port_check
    participant Zenohd as zenohd プロセス

    Handler->>ZenohdMgr: run()
    ZenohdMgr->>ZenohdMgr: is_running()?
    alt 既に起動中
        ZenohdMgr-->>Handler: Ok(())
    else 未起動
        ZenohdMgr->>Zenohd: Command::new("zenohd").spawn()
        ZenohdMgr->>ZenohdMgr: child を保持
        ZenohdMgr->>PortCheck: wait_for_zenohd()
        loop 最大60秒
            PortCheck->>PortCheck: TcpStream::connect(127.0.0.1:7447)
            alt 接続成功
                PortCheck-->>ZenohdMgr: true
            else 失敗
                PortCheck->>PortCheck: sleep(1秒)
            end
        end
        alt タイムアウト
            ZenohdMgr->>ZenohdMgr: quit()
            ZenohdMgr-->>Handler: Err
        else 成功
            ZenohdMgr-->>Handler: Ok(())
        end
    end
```

### 8.4 zenohd Quit シーケンス

```mermaid
sequenceDiagram
    participant Handler as handle_menu_event
    participant ZenohdMgr as ZenohdManager
    participant Child as Child プロセス

    Handler->>ZenohdMgr: quit()
    ZenohdMgr->>ZenohdMgr: child.lock()
    ZenohdMgr->>ZenohdMgr: child.take()
    ZenohdMgr->>Child: kill()
    ZenohdMgr-->>Handler: (戻る)
    Handler->>Handler: MenuItems.set_enabled()
```

### 8.5 HL-Server Run シーケンス

```mermaid
sequenceDiagram
    participant Handler as handle_menu_event
    participant HlSvrMgr as HlServerManager
    participant Config as config
    participant PortCheck as port_check
    participant MixRun as mix run プロセス

    Handler->>HlSvrMgr: run()
    HlSvrMgr->>HlSvrMgr: is_running()?
    alt 既に起動中
        HlSvrMgr-->>Handler: Ok(())
    else 未起動
        HlSvrMgr->>Config: mix_work_dir()
        HlSvrMgr->>HlSvrMgr: mix.exs 存在確認
        alt mix.exs なし
            HlSvrMgr-->>Handler: Err
        else あり
            HlSvrMgr->>MixRun: cmd /c "cd ROOT && mix run --no-halt"
            HlSvrMgr->>HlSvrMgr: child を保持
            HlSvrMgr->>PortCheck: wait_for_hl_server()
            loop 最大60秒
                PortCheck->>PortCheck: TcpStream::connect(127.0.0.1:4000)
                alt 接続成功
                    PortCheck-->>HlSvrMgr: true
                else 失敗
                    PortCheck->>PortCheck: sleep(1秒)
                end
            end
            alt タイムアウト
                HlSvrMgr->>HlSvrMgr: quit()
                HlSvrMgr-->>Handler: Err
            else 成功
                HlSvrMgr-->>Handler: Ok(())
            end
        end
    end
```

### 8.6 Client Run シーケンス

```mermaid
sequenceDiagram
    participant Handler as handle_menu_event
    participant Client as run_client
    participant PortCheck as port_check
    participant Config as config
    participant DesktopClient as desktop_client

    Handler->>Client: run_client(zenohd_ready, hl_server_ready)
    alt zenohd 未起動
        Client->>PortCheck: wait_for_zenohd()
        alt タイムアウト
            Client-->>Handler: Err
        end
    end
    alt hl_server 未起動
        Client->>PortCheck: wait_for_hl_server()
        alt タイムアウト
            Client-->>Handler: Err
        end
    end
    Client->>Config: desktop_client_exe()
    alt exe 存在
        Client->>DesktopClient: desktop_client.exe --connect ... --room ...
    else exe なし
        Client->>DesktopClient: cargo run -p desktop_client ...
    end
    Client-->>Handler: Ok(Child)
```

### 8.7 ポート待機シーケンス（wait_for_port）

```mermaid
sequenceDiagram
    participant Caller as 呼び出し元
    participant WaitForPort as wait_for_port
    participant TcpStream as TcpStream
    participant Target as 対象サービス(zenohd/HL-Server)

    Caller->>WaitForPort: wait_for_port(check_fn, label)
    loop start.elapsed() < 60秒
        WaitForPort->>WaitForPort: check_fn()
        WaitForPort->>TcpStream: connect_timeout(127.0.0.1:port, 2秒)
        alt 接続成功
            TcpStream->>Target: 接続
            WaitForPort-->>Caller: true
        else 失敗
            WaitForPort->>WaitForPort: thread::sleep(1秒)
        end
    end
    WaitForPort-->>Caller: false（タイムアウト）
```

---

## 9. リリース後の単体動作

**結論: 現状の実装では、ランチャー単体では動作しません。**

リリース製品として配布した場合、以下が前提となり、そのままでは単体動作しません。

| 依存 | 現状 | リリース時の課題 |
|:---|:---|:---|
| **パス解決** | exe が `native/target/release/launcher.exe` にあることを前提にプロジェクトルートを推定 | インストール先（例: `C:\Program Files\AlchemyEngine\`）では `native/` 構造が存在せず、`mix.exs` や `desktop_client` を発見できない |
| **zenohd** | PATH 上の `zenohd` を呼び出し | エンドユーザー環境に zenohd がインストールされていない可能性が高い。同梱 or 別途インストール手順が必要 |
| **HL-Server (mix run)** | プロジェクトルートで `mix run --no-halt` を実行 | リリース時は Elixir ソースではなく **Elixir release**（ビルド済みバイナリ）を配布する想定。`mix run` は開発専用 |
| **desktop_client** | `native/target/release/desktop_client.exe` を参照 | インストールディレクトリ構成が変わるとパスが合わない |

**リリース向けに単体動作させるには、次が必要です。**

1. **インストール構成に合わせたパス解決**
   - `config/launcher.toml` や環境変数でインストールルートを指定
   - 例: `--root` オプション、`ALCHEMY_ROOT` 環境変数

2. **zenohd の扱い**
   - zenohd を同梱して相対パスで起動する、または
   - インストーラで zenohd を別途インストールする

3. **HL-Server の起動方法の切り替え**
   - 開発: `mix run --no-halt`
   - リリース: `bin/start` や Elixir release の `./alchemy start` など、ビルド済みサーバー起動コマンドに切り替え

4. **desktop_client のパス指定**
   - インストール後の `desktop_client.exe` の絶対パス or 相対パスを設定で指定

設計書 6.2 の `config/launcher.toml` でこれらのパスを上書き可能にすれば、リリース構成に対応できます。

---

## 10. 課題（将来対応）

| 課題 | 内容 | 現状 |
|:---|:---|:---|
| **zenohd の起動方式（Windows）** | Windows では `cmd /c start zenohd` で直接起動するとポート 7447 が応答しない場合があり、`bin/start_zenohd.bat` を経由して起動している | 開発環境では動作する。本番環境では zenohd を直接 spawn する方式への移行が望ましい |

---

## 11. 関連ドキュメント

- [client-server-separation-procedure.md](./client-server-separation-procedure.md) — クライアント・サーバー分離（将来課題の zenohd トレイを本設計に統合）
- [cross-compile.md](../cross-compile.md) — ビルド・配布手順
- [contents-defines-rust-executes.md](./contents-defines-rust-executes.md) — 定義 vs 実行の分離

