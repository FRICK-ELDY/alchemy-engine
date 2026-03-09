//! Phase 6: zenohd + HL-Server + Client Run + Check for Update / acknowledgements
//!
//! トレイアイコン表示、メニューから zenohd と mix run を起動・終了。
//! Check for Update で GitHub releases を確認。acknowledgements で謝辞・ライセンスを表示。
//!
//! TODO: zenohd と Phoenix Server のメニューイベント処理が同パターンで重複している。
//! 将来的に ServiceManager のような共通 abstraction でまとめると保守しやすい。

use std::cell::RefCell;
use std::env;
use std::net::{SocketAddr, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::rc::Rc;
use std::thread;
use std::time::{Duration, Instant};

/// GitHub API で取得するリポジトリ
const GITHUB_REPO: &str = "FRICK-ELDY/alchemy-engine";
use kill_tree::blocking::kill_tree;
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use tray_icon::{
    menu::{Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem, Submenu},
    Icon, TrayIcon, TrayIconBuilder, TrayIconEvent,
};

/// zenohd の待ち受けポート
const ZENOHD_PORT: u16 = 7447;
/// Phoenix Server (mix run) の待ち受けポート
const PHOENIX_SERVER_PORT: u16 = 4000;
/// ポート確認の接続タイムアウト（1 回あたり）
const PORT_CONNECT_TIMEOUT: Duration = Duration::from_secs(2);
/// 最大待機時間
const PORT_WAIT_TIMEOUT: Duration = Duration::from_secs(60);
/// ポーリング間隔
const PORT_POLL_INTERVAL: Duration = Duration::from_secs(1);

// アイコン用の定数
const ICON_SIZE: u32 = 16;
const ICON_MARGIN: u32 = 2;
const ICON_ALPHA_EDGE: u8 = 0x80;
const ICON_ALPHA_CENTER: u8 = 0xFF;

/// 灰色アイコン用（zenohd / Phoenix Server のいずれかが未起動）
const ICON_GRAY_R: u8 = 0x80;
const ICON_GRAY_G: u8 = 0x80;
const ICON_GRAY_B: u8 = 0x80;

/// 緑色アイコン用（両方起動済み）
const ICON_GREEN_R: u8 = 0x22;
const ICON_GREEN_G: u8 = 0x8B;
const ICON_GREEN_B: u8 = 0x22;

/// zenohd は tcp/[::]:7447 で待ち受けるため、IPv4 と IPv6 の両方を試す。
const PORT_CHECK_ADDRESSES: &[&str] = &["127.0.0.1", "[::1]"];

/// zenohd がポートに bind するまでの初回待機。
/// Phoenix は Elixir 起動に数秒かかることもあり、初回チェックが早すぎる可能性はある
/// （設計書「初回待機・ポーリング間隔の見直し」参照）。
const PORT_INITIAL_DELAY: Duration = Duration::from_millis(500);

/// mix.exs を含むプロジェクトルートを探す。
/// 1) current_dir から上位を検索（cargo run 時は通常プロジェクトルートになる）
/// 2) 見つからなければ実行ファイルの親から検索（exe 直接起動時は current_dir が不定のため）
///
/// 境界値: exe.parent() が None になる（ルート直下など）稀なケースでは None を返す。
fn find_project_root() -> Option<PathBuf> {
    if let Some(root) = search_mix_exs_upward(std::env::current_dir().ok()?) {
        return Some(root);
    }
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(PathBuf::from))
        .and_then(search_mix_exs_upward)
}

fn search_mix_exs_upward(mut dir: PathBuf) -> Option<PathBuf> {
    loop {
        if dir.join("mix.exs").is_file() {
            return Some(dir);
        }
        if !dir.pop() {
            return None;
        }
    }
}

/// Elixir の検索対象ディレクトリ。mix_path_with_elixir_dirs と find_mix_exe で共通利用。
#[cfg(windows)]
fn elixir_search_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(local) = env::var_os("LOCALAPPDATA") {
        dirs.push(
            Path::new(&local)
                .join("Programs")
                .join("Elixir")
                .join("bin"),
        );
    }
    if let Some(pf) = env::var_os("ProgramFiles") {
        dirs.push(Path::new(&pf).join("Elixir").join("bin"));
    }
    if let Some(pf86) = env::var_os("ProgramFiles(x86)") {
        dirs.push(Path::new(&pf86).join("Elixir").join("bin"));
    }
    dirs.push(PathBuf::from(r"C:\Program Files\Elixir\bin"));
    dirs.push(PathBuf::from(r"C:\Program Files (x86)\Elixir\bin"));
    dirs.push(PathBuf::from(
        r"C:\ProgramData\chocolatey\lib\elixir\tools\bin",
    ));
    dirs.push(PathBuf::from(r"C:\ProgramData\chocolatey\bin"));
    dirs
}

/// mix 実行用の PATH。Windows の GUI アプリはターミナルと環境が異なるため、
/// よくある Elixir のインストールパスを先頭に追加する。
///
/// PATH が未設定の環境（極端なケース）では None を返す。その場合 spawn_mix_run の
/// フォールバックでは cmd.env("PATH", path) が呼ばれず、親プロセスの環境継承のみとなる。
#[cfg(windows)]
fn mix_path_with_elixir_dirs() -> Option<std::ffi::OsString> {
    let base_path = env::var_os("PATH")?;
    let prepend: Vec<PathBuf> = elixir_search_dirs()
        .into_iter()
        .filter(|p| p.exists())
        .collect();
    if prepend.is_empty() {
        return Some(base_path);
    }
    let path_sep = ";";
    let new_path = prepend
        .iter()
        .map(|p| p.to_string_lossy())
        .chain([base_path.to_string_lossy()])
        .collect::<Vec<_>>()
        .join(path_sep);
    Some(new_path.into())
}

#[cfg(not(windows))]
fn mix_path_with_elixir_dirs() -> Option<std::ffi::OsString> {
    env::var_os("PATH")
}

/// Windows: PATH の先頭に %USERPROFILE%\.cargo\bin を追加。
/// GUI アプリ経由起動では PATH が限られることがあるため、bin\windows_client.bat と同様の対応。
#[cfg(windows)]
fn path_with_cargo_bin() -> std::ffi::OsString {
    let base = env::var_os("PATH").unwrap_or_default();
    if let Some(home) = env::var_os("USERPROFILE") {
        let cargo_bin = Path::new(&home).join(".cargo").join("bin");
        if cargo_bin.exists() {
            let prepend = cargo_bin.to_string_lossy();
            let rest = base.to_string_lossy();
            return format!("{};{}", prepend, rest).into();
        }
    }
    base
}

/// mix.bat / mix.exe のフルパスを検索する。見つかれば Some を返す。
#[cfg(windows)]
fn find_mix_exe() -> Option<PathBuf> {
    // 環境変数で指定されていればそれを使用（例: ALCHEMY_MIX_PATH=C:\...\mix.bat または ...\bin）
    if let Ok(p) = env::var("ALCHEMY_MIX_PATH") {
        let path = PathBuf::from(&p);
        if path.is_file() {
            return Some(path);
        }
        for name in ["mix.bat", "mix.exe"] {
            let full = path.join(name);
            if full.is_file() {
                return Some(full);
            }
        }
    }
    for dir in elixir_search_dirs() {
        let mix_bat = dir.join("mix.bat");
        let mix_exe = dir.join("mix.exe");
        if mix_bat.is_file() {
            return Some(mix_bat);
        }
        if mix_exe.is_file() {
            return Some(mix_exe);
        }
    }
    None
}

/// Windows: mix を起動する。mix.bat/mix.exe のフルパスが分かれば、その bin を PATH 先頭に追加して mix を実行。
#[cfg(windows)]
fn spawn_mix_run(project_root: &Path) -> std::io::Result<Child> {
    if let Some(mix_path) = find_mix_exe() {
        if let Some(mix_dir) = mix_path.parent() {
            let base_path = env::var_os("PATH").unwrap_or_default();
            let new_path = format!("{};{}", mix_dir.display(), base_path.to_string_lossy());
            return Command::new("cmd")
                .args(["/c", "mix", "run", "--no-halt"])
                .current_dir(project_root)
                .env("PATH", &new_path)
                .spawn();
        }
    }
    // フォールバック: cmd 経由で mix を探す
    let mut cmd = Command::new("cmd");
    cmd.args(["/c", "mix", "run", "--no-halt"])
        .current_dir(project_root);
    if let Some(path) = mix_path_with_elixir_dirs() {
        cmd.env("PATH", path);
    }
    cmd.spawn()
}

#[cfg(not(windows))]
fn spawn_mix_run(project_root: &Path) -> std::io::Result<Child> {
    let mut cmd = Command::new("mix");
    cmd.args(["run", "--no-halt"]).current_dir(project_root);
    if let Some(path) = mix_path_with_elixir_dirs() {
        cmd.env("PATH", path);
    }
    cmd.spawn()
}

/// 16x16 のプレースホルダーアイコン。r,g,b で色を指定。
fn create_icon_with_color(r: u8, g: u8, b: u8) -> Icon {
    let mut rgba = Vec::with_capacity((ICON_SIZE * ICON_SIZE * 4) as usize);
    for y in 0..ICON_SIZE {
        for x in 0..ICON_SIZE {
            let a = if (x > ICON_MARGIN && x < ICON_SIZE - ICON_MARGIN - 1)
                && (y > ICON_MARGIN && y < ICON_SIZE - ICON_MARGIN - 1)
            {
                ICON_ALPHA_CENTER
            } else {
                ICON_ALPHA_EDGE
            };
            rgba.extend_from_slice(&[r, g, b, a]);
        }
    }
    Icon::from_rgba(rgba, ICON_SIZE, ICON_SIZE).expect("Failed to create icon")
}

/// ポートが応答するまで待機する。
///
/// - 成功: `true` を返す（いずれかのアドレスに接続できた場合）
/// - タイムアウト: `false` を返す
/// - 接続試行中の I/O エラーは無視してリトライを続ける
/// - `skip_initial_delay`: true なら初回待機を省略（連続呼び出し時の累積遅延短縮用）
fn wait_for_port(port: u16, timeout: Duration, skip_initial_delay: bool) -> bool {
    // PORT_CHECK_ADDRESSES は固定リテラルなので parse は通常成功する。アドレス編集時に
    // 不正が混入した場合のみ None となり、その場合は静かにスキップする。
    let addrs: Vec<SocketAddr> = PORT_CHECK_ADDRESSES
        .iter()
        .filter_map(|host| format!("{}:{}", host, port).parse().ok())
        .collect();
    if addrs.is_empty() {
        eprintln!("[launcher] No valid port check addresses");
        return false;
    }
    if !skip_initial_delay {
        thread::sleep(PORT_INITIAL_DELAY);
    }
    let start = Instant::now();
    while start.elapsed() < timeout {
        for addr in &addrs {
            if TcpStream::connect_timeout(addr, PORT_CONNECT_TIMEOUT).is_ok() {
                return true;
            }
        }
        thread::sleep(PORT_POLL_INTERVAL);
    }
    false
}

/// zenohd を終了（同期）。アプリ終了時に使用。
fn terminate_zenohd_sync(mut child: Child, submenu: &Submenu) {
    let pid = child.id();
    if let Err(e) = kill_tree(pid) {
        eprintln!("zenohd の終了に失敗しました: {}", e);
    }
    let _ = child.wait();
    submenu.set_text("Zenoh Router : OFF");
}

/// Phoenix Server を終了（同期）。アプリ終了時に使用。
fn terminate_phoenix_server_sync(mut child: Child, submenu: &Submenu) {
    let pid = child.id();
    if let Err(e) = kill_tree(pid) {
        eprintln!("Phoenix Server の終了に失敗しました: {}", e);
    }
    let _ = child.wait();
    submenu.set_text("Phoenix Server : OFF");
}

/// app の exe パスを検索。release を優先、なければ debug。
fn find_app_exe(project_root: &Path) -> Option<PathBuf> {
    let native_dir = project_root.join("native");
    let release = native_dir
        .join("target")
        .join("release")
        .join(exe_name("app"));
    if release.is_file() {
        return Some(release);
    }
    let debug = native_dir
        .join("target")
        .join("debug")
        .join(exe_name("app"));
    if debug.is_file() {
        return Some(debug);
    }
    None
}

#[cfg(windows)]
fn exe_name(base: &str) -> String {
    format!("{}.exe", base)
}
#[cfg(not(windows))]
fn exe_name(base: &str) -> String {
    base.to_string()
}

/// app を起動。zenohd と Phoenix Server のポート確認後に spawn。
/// 成功時は Ok(Child)、失敗時は Err(msg)。
fn spawn_app(project_root: &Path) -> Result<Child, String> {
    if !wait_for_port(ZENOHD_PORT, PORT_WAIT_TIMEOUT, false) {
        return Err(format!(
            "Zenoh Router (port {}) did not respond within {} seconds.\n\nStart Zenoh Router first.",
            ZENOHD_PORT,
            PORT_WAIT_TIMEOUT.as_secs()
        ));
    }
    if !wait_for_port(PHOENIX_SERVER_PORT, PORT_WAIT_TIMEOUT, true) {
        return Err(format!(
            "Phoenix Server (port {}) did not respond within {} seconds.\n\nStart Phoenix Server first.",
            PHOENIX_SERVER_PORT,
            PORT_WAIT_TIMEOUT.as_secs()
        ));
    }
    // TODO: 環境変数や config で接続先を切り替え可能にする
    let connect = "tcp/127.0.0.1:7447";
    let room = "main";

    let manifest = project_root.join("native").join("Cargo.toml");
    if !manifest.is_file() {
        return Err("native/Cargo.toml not found. Project structure may be invalid. Run the launcher from the project root.".to_string());
    }

    if let Some(exe) = find_app_exe(project_root) {
        Command::new(exe)
            .args(["--connect", connect, "--room", room])
            .current_dir(project_root)
            .spawn()
            .map_err(|e| format!("Failed to start app: {}", e))
    } else {
        let manifest_str = manifest.to_string_lossy();
        #[cfg(windows)]
        {
            Command::new("cmd")
                .args([
                    "/c",
                    "cargo",
                    "run",
                    "--manifest-path",
                    &manifest_str,
                    "-p",
                    "app",
                    "--",
                    "--connect",
                    connect,
                    "--room",
                    room,
                ])
                .current_dir(project_root)
                .env("PATH", path_with_cargo_bin())
                .spawn()
                .map_err(|e| format!("Failed to run app (cargo run): {}", e))
        }
        #[cfg(not(windows))]
        {
            Command::new("cargo")
                .args([
                    "run",
                    "--manifest-path",
                    &manifest_str,
                    "-p",
                    "app",
                    "--",
                    "--connect",
                    connect,
                    "--room",
                    room,
                ])
                .current_dir(project_root)
                .spawn()
                .map_err(|e| format!("Failed to run app (cargo run): {}", e))
        }
    }
}

/// GitHub releases API で最新バージョンを取得。比較してメッセージを返す。
///
/// 現状は UI スレッドとは別スレッドで呼ばれるためブロックは許容されるが、?
/// 将来的にタイムアウト延長や複数 API 呼び出しを行う場合は非同期化の検討余地あり。
fn check_for_update() -> Result<String, String> {
    let url = format!(
        "https://api.github.com/repos/{}/releases/latest",
        GITHUB_REPO
    );
    let client = reqwest::blocking::Client::builder()
        .user_agent("AlchemyEngine-Launcher")
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {}", e))?;
    let resp = client
        .get(&url)
        .send()
        .map_err(|e| format!("Network error: {}", e))?;
    if !resp.status().is_success() {
        let status = resp.status();
        let hint = if status.as_u16() == 403 {
            " Rate limiting (e.g. 60 req/h unauthenticated) may apply."
        } else {
            ""
        };
        return Err(format!(
            "Could not fetch release info (HTTP {}).{}\n\nIf the repository is private or has no releases, this is expected.",
            status, hint
        ));
    }
    let json: serde_json::Value = resp.json().map_err(|e| format!("Invalid JSON: {}", e))?;
    let tag = json
        .get("tag_name")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "No tag_name in response".to_string())?;
    let latest = tag.trim_start_matches('v');
    let current = env!("CARGO_PKG_VERSION");
    match (
        semver::Version::parse(current),
        semver::Version::parse(latest),
    ) {
        (Ok(cur), Ok(lat)) => {
            if lat > cur {
                Ok(format!(
                    "A new version is available.\n\nCurrent: {}\nLatest:  {}\n\nhttps://github.com/{}/releases",
                    current, latest, GITHUB_REPO
                ))
            } else {
                Ok(format!("You are up to date.\n\nVersion: {}", current))
            }
        }
        _ => Ok(format!("Current version: {}\nLatest tag: {}", current, tag)),
    }
}

fn main() {
    let event_loop = EventLoopBuilder::with_user_event().build();
    let proxy = event_loop.create_proxy();

    enum UserEvent {
        TrayIcon(TrayIconEvent),
        Menu(MenuEvent),
        ZenohdQuitComplete,
        ZenohdReady,
        ZenohdStartFailed(String),
        PhoenixServerQuitComplete,
        PhoenixServerReady,
        PhoenixServerStartFailed(String),
        ClientRunFailed(String),
        CheckForUpdateResult(Result<String, String>),
    }

    TrayIconEvent::set_event_handler(Some({
        let proxy = proxy.clone();
        move |event| {
            let _ = proxy.send_event(UserEvent::TrayIcon(event));
        }
    }));

    MenuEvent::set_event_handler(Some({
        let proxy = proxy.clone();
        move |event| {
            let _ = proxy.send_event(UserEvent::Menu(event));
        }
    }));

    let check_for_update_id = MenuId::new("check_for_update");
    let acknowledgements_id = MenuId::new("acknowledgements");
    let zenohd_about_id = MenuId::new("zenohd_about");
    let zenohd_run_id = MenuId::new("zenohd_run");
    let zenohd_quit_id = MenuId::new("zenohd_quit");
    let phoenix_about_id = MenuId::new("phoenix_about");
    let phoenix_run_id = MenuId::new("phoenix_run");
    let phoenix_quit_id = MenuId::new("phoenix_quit");
    let client_run_id = MenuId::new("client_run");
    let quit_id = MenuId::new("quit");

    let check_for_update_item = MenuItem::with_id(
        check_for_update_id.clone(),
        "Check for Update...",
        true,
        None,
    );
    let acknowledgements_item =
        MenuItem::with_id(acknowledgements_id.clone(), "acknowledgements", true, None);
    let zenohd_about_item = MenuItem::with_id(zenohd_about_id.clone(), "About", true, None);
    let zenohd_run_item = MenuItem::with_id(zenohd_run_id.clone(), "Run", true, None);
    let zenohd_quit_item = MenuItem::with_id(zenohd_quit_id.clone(), "Quit", true, None);
    let phoenix_about_item = MenuItem::with_id(phoenix_about_id.clone(), "About", true, None);
    let phoenix_run_item = MenuItem::with_id(phoenix_run_id.clone(), "Run", true, None);
    let phoenix_quit_item = MenuItem::with_id(phoenix_quit_id.clone(), "Quit", true, None);

    let zenohd_submenu = Rc::new(Submenu::new("Zenoh Router : OFF", true));
    zenohd_submenu
        .append(&zenohd_about_item)
        .expect("Failed to append about");
    zenohd_submenu
        .append(&zenohd_run_item)
        .expect("Failed to append run");
    zenohd_submenu
        .append(&zenohd_quit_item)
        .expect("Failed to append quit");

    let phoenix_submenu = Rc::new(Submenu::new("Phoenix Server : OFF", true));
    phoenix_submenu
        .append(&phoenix_about_item)
        .expect("Failed to append about");
    phoenix_submenu
        .append(&phoenix_run_item)
        .expect("Failed to append run");
    phoenix_submenu
        .append(&phoenix_quit_item)
        .expect("Failed to append quit");

    let client_run_item = MenuItem::with_id(client_run_id.clone(), "Client Run", true, None);
    let quit_item = MenuItem::with_id(quit_id.clone(), "Quit", true, None);

    let menu = Menu::new();
    menu.append(&check_for_update_item)
        .expect("Failed to append check for update");
    menu.append(&acknowledgements_item)
        .expect("Failed to append acknowledgements");
    menu.append(&PredefinedMenuItem::separator())
        .expect("Failed to append separator");
    menu.append(zenohd_submenu.as_ref())
        .expect("Failed to append submenu");
    menu.append(phoenix_submenu.as_ref())
        .expect("Failed to append submenu");
    menu.append(&PredefinedMenuItem::separator())
        .expect("Failed to append separator");
    menu.append(&client_run_item)
        .expect("Failed to append client run");
    menu.append(&PredefinedMenuItem::separator())
        .expect("Failed to append separator");
    menu.append(&quit_item).expect("Failed to append menu item");

    let tray_icon: Rc<TrayIcon> = Rc::new(
        TrayIconBuilder::new()
            .with_menu(Box::new(menu))
            .with_tooltip("AlchemyEngine")
            .with_icon(create_icon_with_color(
                ICON_GRAY_R,
                ICON_GRAY_G,
                ICON_GRAY_B,
            ))
            .build()
            .expect("Failed to create tray icon"),
    );
    tray_icon.set_show_menu_on_left_click(false);

    let zenohd_child: Rc<RefCell<Option<Child>>> = Rc::new(RefCell::new(None));
    let zenohd_submenu = Rc::clone(&zenohd_submenu);
    let zenohd_starting_cancelled = Rc::new(RefCell::new(false));
    let zenohd_ready = Rc::new(RefCell::new(false));

    let phoenix_child: Rc<RefCell<Option<Child>>> = Rc::new(RefCell::new(None));
    let phoenix_submenu = Rc::clone(&phoenix_submenu);
    let phoenix_starting_cancelled = Rc::new(RefCell::new(false));
    let phoenix_ready = Rc::new(RefCell::new(false));

    let update_menu_and_icon = {
        let zenohd_child = Rc::clone(&zenohd_child);
        let phoenix_child = Rc::clone(&phoenix_child);
        let zenohd_run_item = zenohd_run_item.clone();
        let zenohd_quit_item = zenohd_quit_item.clone();
        let phoenix_run_item = phoenix_run_item.clone();
        let phoenix_quit_item = phoenix_quit_item.clone();
        let zenohd_ready = Rc::clone(&zenohd_ready);
        let phoenix_ready = Rc::clone(&phoenix_ready);
        let tray_icon = Rc::clone(&tray_icon);
        move || {
            let zh = zenohd_child.borrow().is_some();
            let ph = phoenix_child.borrow().is_some();
            zenohd_run_item.set_enabled(!zh);
            zenohd_quit_item.set_enabled(zh);
            phoenix_run_item.set_enabled(!ph);
            phoenix_quit_item.set_enabled(ph);
            let both_ready = *zenohd_ready.borrow() && *phoenix_ready.borrow();
            let icon = if both_ready {
                create_icon_with_color(ICON_GREEN_R, ICON_GREEN_G, ICON_GREEN_B)
            } else {
                create_icon_with_color(ICON_GRAY_R, ICON_GRAY_G, ICON_GRAY_B)
            };
            let _ = tray_icon.set_icon(Some(icon));
        }
    };

    update_menu_and_icon();

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Poll;

        // zenohd がクラッシュ・外部終了した場合の検知
        let zenohd_crash = {
            let mut child_opt = zenohd_child.borrow_mut();
            if let Some(ref mut child) = *child_opt {
                if child.try_wait().ok().flatten().is_some() {
                    *child_opt = None;
                    *zenohd_ready.borrow_mut() = false;
                    zenohd_submenu.set_text("Zenoh Router : OFF");
                    true
                } else {
                    false
                }
            } else {
                false
            }
        };
        if zenohd_crash {
            update_menu_and_icon();
        }

        // Phoenix Server がクラッシュ・外部終了した場合の検知
        let phoenix_crash = {
            let mut child_opt = phoenix_child.borrow_mut();
            if let Some(ref mut child) = *child_opt {
                if child.try_wait().ok().flatten().is_some() {
                    *child_opt = None;
                    *phoenix_ready.borrow_mut() = false;
                    phoenix_submenu.set_text("Phoenix Server : OFF");
                    true
                } else {
                    false
                }
            } else {
                false
            }
        };
        if phoenix_crash {
            update_menu_and_icon();
        }

        if let tao::event::Event::UserEvent(user_event) = event {
            match user_event {
                UserEvent::Menu(menu_event) => {
                    if menu_event.id == check_for_update_id {
                        let proxy = proxy.clone();
                        thread::spawn(move || {
                            let result = check_for_update();
                            let _ = proxy.send_event(UserEvent::CheckForUpdateResult(result));
                        });
                    } else if menu_event.id == acknowledgements_id {
                        let text = include_str!("../acknowledgements.txt");
                        rfd::MessageDialog::new()
                            .set_title("Acknowledgements")
                            .set_description(text)
                            .set_level(rfd::MessageLevel::Info)
                            .show();
                    } else if menu_event.id == zenohd_about_id {
                        rfd::MessageDialog::new()
                            .set_title("Zenoh Router — About")
                            .set_description(
                                "Zenoh Router (zenohd)\n\n\
                                Message broker for AlchemyEngine. Listens on port 7447 (TCP).\n\
                                Relays game state and input between the Phoenix Server and desktop clients.\n\n\
                                Install: cargo install eclipse-zenoh",
                            )
                            .set_level(rfd::MessageLevel::Info)
                            .show();
                    } else if menu_event.id == phoenix_about_id {
                        rfd::MessageDialog::new()
                            .set_title("Phoenix Server — About")
                            .set_description(
                                "Phoenix Server (mix run)\n\n\
                                Elixir-based game server. Listens on port 4000 (HTTP/WebSocket).\n\
                                Runs game logic, physics, and room state. Connects to Zenoh Router for client communication.\n\n\
                                Requires Elixir and mix in PATH.",
                            )
                            .set_level(rfd::MessageLevel::Info)
                            .show();
                    } else if menu_event.id == zenohd_run_id {
                        let zenohd_started = {
                            let mut child_opt = zenohd_child.borrow_mut();
                            if child_opt.is_none() {
                                match Command::new("zenohd").spawn() {
                                    Ok(child) => {
                                        *child_opt = Some(child);
                                        *zenohd_starting_cancelled.borrow_mut() = false;
                                        zenohd_submenu.set_text("Zenoh Router : Starting...");
                                        let proxy = proxy.clone();
                                        thread::spawn(move || {
                                            if wait_for_port(ZENOHD_PORT, PORT_WAIT_TIMEOUT, false) {
                                                let _ = proxy.send_event(UserEvent::ZenohdReady);
                                            } else {
                                                let _ = proxy.send_event(UserEvent::ZenohdStartFailed(
                                                    format!(
                                                        "Zenoh Router failed to start.\n\nPort {} did not respond within {} seconds.\n\nPlease ensure zenohd is installed correctly.",
                                                        ZENOHD_PORT,
                                                        PORT_WAIT_TIMEOUT.as_secs()
                                                    ),
                                                ));
                                            }
                                        });
                                        true
                                    }
                                    Err(e) => {
                                        let msg = format!("Failed to start zenohd: {}", e);
                                        rfd::MessageDialog::new()
                                            .set_title("Zenoh Router Start Failed")
                                            .set_description(&msg)
                                            .set_level(rfd::MessageLevel::Error)
                                            .show();
                                        false
                                    }
                                }
                            } else {
                                false
                            }
                        };
                        if zenohd_started {
                            update_menu_and_icon();
                        }
                    } else if menu_event.id == zenohd_quit_id {
                        let zenohd_quitting = {
                            let mut child_opt = zenohd_child.borrow_mut();
                            if let Some(mut child) = child_opt.take() {
                                *zenohd_starting_cancelled.borrow_mut() = true;
                                let pid = child.id();
                                let proxy = proxy.clone();
                                thread::spawn(move || {
                                    if let Err(e) = kill_tree(pid) {
                                        eprintln!("zenohd の終了に失敗しました: {}", e);
                                    }
                                    let _ = child.wait();
                                    let _ = proxy.send_event(UserEvent::ZenohdQuitComplete);
                                });
                                zenohd_submenu.set_text("Zenoh Router : OFF");
                                true
                            } else {
                                false
                            }
                        };
                        if zenohd_quitting {
                            update_menu_and_icon();
                        }
                    } else if menu_event.id == phoenix_run_id {
                        let phoenix_started = {
                            let mut child_opt = phoenix_child.borrow_mut();
                            if child_opt.is_none() {
                                if let Some(project_root) = find_project_root() {
                                    match spawn_mix_run(&project_root) {
                                        Ok(child) => {
                                            *child_opt = Some(child);
                                            *phoenix_starting_cancelled.borrow_mut() = false;
                                            phoenix_submenu.set_text("Phoenix Server : Starting...");
                                            let proxy = proxy.clone();
                                            thread::spawn(move || {
                                                if wait_for_port(PHOENIX_SERVER_PORT, PORT_WAIT_TIMEOUT, false) {
                                                    let _ = proxy.send_event(UserEvent::PhoenixServerReady);
                                                } else {
                                                    let _ = proxy.send_event(
                                                        UserEvent::PhoenixServerStartFailed(format!(
                                                            "Phoenix Server failed to start.\n\nPort {} did not respond within {} seconds.",
                                                            PHOENIX_SERVER_PORT,
                                                            PORT_WAIT_TIMEOUT.as_secs()
                                                        )),
                                                    );
                                                }
                                            });
                                            true
                                        }
                                        Err(e) => {
                                            let msg = format!(
                                                "Failed to start Phoenix Server: {}\n\nEnsure Elixir and mix are installed.",
                                                e
                                            );
                                            rfd::MessageDialog::new()
                                                .set_title("Phoenix Server Start Failed")
                                                .set_description(&msg)
                                                .set_level(rfd::MessageLevel::Error)
                                                .show();
                                            false
                                        }
                                    }
                                } else {
                                    rfd::MessageDialog::new()
                                        .set_title("Phoenix Server Start Failed")
                                        .set_description("mix.exs not found. Run the launcher from the project directory.")
                                        .set_level(rfd::MessageLevel::Error)
                                        .show();
                                    false
                                }
                            } else {
                                false
                            }
                        };
                        if phoenix_started {
                            update_menu_and_icon();
                        }
                    } else if menu_event.id == phoenix_quit_id {
                        let phoenix_quitting = {
                            let mut child_opt = phoenix_child.borrow_mut();
                            if let Some(mut child) = child_opt.take() {
                                *phoenix_starting_cancelled.borrow_mut() = true;
                                let pid = child.id();
                                let proxy = proxy.clone();
                                thread::spawn(move || {
                                    if let Err(e) = kill_tree(pid) {
                                        eprintln!("Phoenix Server の終了に失敗しました: {}", e);
                                    }
                                    let _ = child.wait();
                                    let _ = proxy.send_event(UserEvent::PhoenixServerQuitComplete);
                                });
                                phoenix_submenu.set_text("Phoenix Server : OFF");
                                true
                            } else {
                                false
                            }
                        };
                        if phoenix_quitting {
                            update_menu_and_icon();
                        }
                    } else if menu_event.id == client_run_id {
                        let proxy = proxy.clone();
                        thread::spawn(move || {
                            let project_root = match find_project_root() {
                                Some(r) => r,
                                None => {
                                    let _ = proxy.send_event(UserEvent::ClientRunFailed(
                                        "mix.exs not found. Run the launcher from the project directory.".to_string(),
                                    ));
                                    return;
                                }
                            };
                            match spawn_app(&project_root) {
                                Ok(_child) => {
                                    // Child を意図的にドロップ。Unix では init に reparent され、
                                    // Windows では親が終了しても子は継続する。トレイでは管理しない。
                                }
                                Err(msg) => {
                                    let _ = proxy.send_event(UserEvent::ClientRunFailed(msg));
                                }
                            }
                        });
                    } else if menu_event.id == quit_id {
                        let mut child_opt = zenohd_child.borrow_mut();
                        if let Some(child) = child_opt.take() {
                            terminate_zenohd_sync(child, &zenohd_submenu);
                        }
                        let mut child_opt = phoenix_child.borrow_mut();
                        if let Some(child) = child_opt.take() {
                            terminate_phoenix_server_sync(child, &phoenix_submenu);
                        }
                        *control_flow = ControlFlow::Exit;
                    }
                }
                // Quit クリック時には既に set_text("OFF") しているが、バックグラウンド終了完了
                // イベントでも再度設定する。try_wait 検知やイベント順序の競合で OFF 表示が
                // 抜ける場合の整合性を保つため。
                UserEvent::ZenohdQuitComplete => {
                    *zenohd_ready.borrow_mut() = false;
                    zenohd_submenu.set_text("Zenoh Router : OFF");
                    update_menu_and_icon();
                }
                // Quit 完了後の遅延 Ready 受信は無視する。cancelled を false に戻すのは
                // 次回 Run に備えてのリセットのみ。他に副作用なし。
                UserEvent::ZenohdReady => {
                    let cancelled = *zenohd_starting_cancelled.borrow();
                    if cancelled {
                        *zenohd_starting_cancelled.borrow_mut() = false;
                    } else {
                        *zenohd_ready.borrow_mut() = true;
                        zenohd_submenu.set_text("Zenoh Router : ON");
                        update_menu_and_icon();
                    }
                }
                UserEvent::ZenohdStartFailed(msg) => {
                    let cancelled = *zenohd_starting_cancelled.borrow();
                    if cancelled {
                        *zenohd_starting_cancelled.borrow_mut() = false;
                    } else {
                        *zenohd_ready.borrow_mut() = false;
                        let mut child_opt = zenohd_child.borrow_mut();
                        if let Some(mut child) = child_opt.take() {
                            let pid = child.id();
                            thread::spawn(move || {
                                if let Err(e) = kill_tree(pid) {
                                    eprintln!("zenohd の終了に失敗しました: {}", e);
                                }
                                if let Err(e) = child.wait() {
                                    eprintln!("zenohd wait エラー: {}", e);
                                }
                            });
                        }
                        zenohd_submenu.set_text("Zenoh Router : OFF");
                        update_menu_and_icon();
                        rfd::MessageDialog::new()
                            .set_title("Zenoh Router Start Failed")
                            .set_description(&msg)
                            .set_level(rfd::MessageLevel::Error)
                            .show();
                    }
                }
                // QuitComplete: 同上（zenohd と同様の整合性保証）
                UserEvent::PhoenixServerQuitComplete => {
                    *phoenix_ready.borrow_mut() = false;
                    phoenix_submenu.set_text("Phoenix Server : OFF");
                    update_menu_and_icon();
                }
                // Ready: zenohd と同様（Quit 完了後の遅延 Ready を無視し、cancelled をリセット）
                UserEvent::PhoenixServerReady => {
                    let cancelled = *phoenix_starting_cancelled.borrow();
                    if cancelled {
                        *phoenix_starting_cancelled.borrow_mut() = false;
                    } else {
                        *phoenix_ready.borrow_mut() = true;
                        phoenix_submenu.set_text("Phoenix Server : ON");
                        update_menu_and_icon();
                    }
                }
                UserEvent::PhoenixServerStartFailed(msg) => {
                    let cancelled = *phoenix_starting_cancelled.borrow();
                    if cancelled {
                        *phoenix_starting_cancelled.borrow_mut() = false;
                    } else {
                        *phoenix_ready.borrow_mut() = false;
                        let mut child_opt = phoenix_child.borrow_mut();
                        if let Some(mut child) = child_opt.take() {
                            let pid = child.id();
                            thread::spawn(move || {
                                if let Err(e) = kill_tree(pid) {
                                    eprintln!("Phoenix Server の終了に失敗しました: {}", e);
                                }
                                if let Err(e) = child.wait() {
                                    eprintln!("Phoenix Server wait エラー: {}", e);
                                }
                            });
                        }
                        phoenix_submenu.set_text("Phoenix Server : OFF");
                        update_menu_and_icon();
                        rfd::MessageDialog::new()
                            .set_title("Phoenix Server Start Failed")
                            .set_description(&msg)
                            .set_level(rfd::MessageLevel::Error)
                            .show();
                    }
                }
                UserEvent::ClientRunFailed(msg) => {
                    rfd::MessageDialog::new()
                        .set_title("Client Run Failed")
                        .set_description(&msg)
                        .set_level(rfd::MessageLevel::Error)
                        .show();
                }
                UserEvent::CheckForUpdateResult(result) => {
                    let (title, level) = match &result {
                        Ok(_) => ("Check for Update", rfd::MessageLevel::Info),
                        Err(_) => ("Check for Update Failed", rfd::MessageLevel::Warning),
                    };
                    let msg = match &result {
                        Ok(s) => s.as_str(),
                        Err(e) => e.as_str(),
                    };
                    rfd::MessageDialog::new()
                        .set_title(title)
                        .set_description(msg)
                        .set_level(level)
                        .show();
                }
                // 将来の拡張用（クリック・ダブルクリックなどの区別など）
                UserEvent::TrayIcon(event) => {
                    let _ = event;
                }
            }
        }
    });
}
