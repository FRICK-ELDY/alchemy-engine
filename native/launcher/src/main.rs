//! Phase 3: zenohd + HL-Server (Phoenix Server) Run / Quit
//!
//! トレイアイコン表示、メニューから zenohd と mix run を起動・終了。
//! ポート確認で成功/失敗を判定。
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
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use kill_tree::blocking::kill_tree;
use tray_icon::{
    menu::{Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem, Submenu},
    Icon, TrayIconBuilder, TrayIconEvent,
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

// アイコン用の色定数（紫系）
const ICON_COLOR_R: u8 = 0x4B;
const ICON_COLOR_G: u8 = 0x27;
const ICON_COLOR_B: u8 = 0x5F;
const ICON_SIZE: u32 = 16;
const ICON_MARGIN: u32 = 2;
const ICON_ALPHA_EDGE: u8 = 0x80;
const ICON_ALPHA_CENTER: u8 = 0xFF;

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
        dirs.push(Path::new(&local).join("Programs").join("Elixir").join("bin"));
    }
    if let Some(pf) = env::var_os("ProgramFiles") {
        dirs.push(Path::new(&pf).join("Elixir").join("bin"));
    }
    if let Some(pf86) = env::var_os("ProgramFiles(x86)") {
        dirs.push(Path::new(&pf86).join("Elixir").join("bin"));
    }
    dirs.push(PathBuf::from(r"C:\Program Files\Elixir\bin"));
    dirs.push(PathBuf::from(r"C:\Program Files (x86)\Elixir\bin"));
    dirs.push(PathBuf::from(r"C:\ProgramData\chocolatey\lib\elixir\tools\bin"));
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
    let prepend: Vec<PathBuf> = elixir_search_dirs().into_iter().filter(|p| p.exists()).collect();
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

/// 16x16 のプレースホルダーアイコン（紫系）
fn create_icon() -> Icon {
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
            rgba.extend_from_slice(&[ICON_COLOR_R, ICON_COLOR_G, ICON_COLOR_B, a]);
        }
    }
    Icon::from_rgba(rgba, ICON_SIZE, ICON_SIZE).expect("Failed to create icon")
}

/// ポートが応答するまで待機する。
///
/// - 成功: `true` を返す（いずれかのアドレスに接続できた場合）
/// - タイムアウト: `false` を返す
/// - 接続試行中の I/O エラーは無視してリトライを続ける
fn wait_for_port(port: u16, timeout: Duration) -> bool {
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
    thread::sleep(PORT_INITIAL_DELAY);
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

    let zenohd_run_id = MenuId::new("zenohd_run");
    let zenohd_quit_id = MenuId::new("zenohd_quit");
    let phoenix_run_id = MenuId::new("phoenix_run");
    let phoenix_quit_id = MenuId::new("phoenix_quit");
    let quit_id = MenuId::new("quit");

    let zenohd_run_item = MenuItem::with_id(zenohd_run_id.clone(), "Run", true, None);
    let zenohd_quit_item = MenuItem::with_id(zenohd_quit_id.clone(), "Quit", true, None);
    let phoenix_run_item = MenuItem::with_id(phoenix_run_id.clone(), "Run", true, None);
    let phoenix_quit_item = MenuItem::with_id(phoenix_quit_id.clone(), "Quit", true, None);

    let zenohd_submenu = Rc::new(Submenu::new("Zenoh Router : OFF", true));
    zenohd_submenu.append(&zenohd_run_item).expect("Failed to append run");
    zenohd_submenu.append(&zenohd_quit_item).expect("Failed to append quit");

    let phoenix_submenu = Rc::new(Submenu::new("Phoenix Server : OFF", true));
    phoenix_submenu.append(&phoenix_run_item).expect("Failed to append run");
    phoenix_submenu.append(&phoenix_quit_item).expect("Failed to append quit");

    let quit_item = MenuItem::with_id(quit_id.clone(), "Quit", true, None);

    let menu = Menu::new();
    menu.append(zenohd_submenu.as_ref()).expect("Failed to append submenu");
    menu.append(phoenix_submenu.as_ref()).expect("Failed to append submenu");
    menu.append(&PredefinedMenuItem::separator()).expect("Failed to append separator");
    menu.append(&quit_item).expect("Failed to append menu item");

    let _tray_icon = TrayIconBuilder::new()
        .with_menu(Box::new(menu))
        .with_tooltip("AlchemyEngine")
        .with_icon(create_icon())
        .build()
        .expect("Failed to create tray icon");

    let zenohd_child: Rc<RefCell<Option<Child>>> = Rc::new(RefCell::new(None));
    let zenohd_submenu = Rc::clone(&zenohd_submenu);
    let zenohd_starting_cancelled = Rc::new(RefCell::new(false));

    let phoenix_child: Rc<RefCell<Option<Child>>> = Rc::new(RefCell::new(None));
    let phoenix_submenu = Rc::clone(&phoenix_submenu);
    let phoenix_starting_cancelled = Rc::new(RefCell::new(false));

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Poll;

        // zenohd がクラッシュ・外部終了した場合の検知
        {
            let mut child_opt = zenohd_child.borrow_mut();
            if let Some(ref mut child) = *child_opt {
                if child.try_wait().ok().flatten().is_some() {
                    *child_opt = None;
                    zenohd_submenu.set_text("Zenoh Router : OFF");
                }
            }
        }

        // Phoenix Server がクラッシュ・外部終了した場合の検知
        {
            let mut child_opt = phoenix_child.borrow_mut();
            if let Some(ref mut child) = *child_opt {
                if child.try_wait().ok().flatten().is_some() {
                    *child_opt = None;
                    phoenix_submenu.set_text("Phoenix Server : OFF");
                }
            }
        }

        if let tao::event::Event::UserEvent(user_event) = event {
            match user_event {
                UserEvent::Menu(menu_event) => {
                    if menu_event.id == zenohd_run_id {
                        let mut child_opt = zenohd_child.borrow_mut();
                        if child_opt.is_none() {
                            match Command::new("zenohd").spawn() {
                                Ok(child) => {
                                    *child_opt = Some(child);
                                    *zenohd_starting_cancelled.borrow_mut() = false;
                                    zenohd_submenu.set_text("Zenoh Router : Starting...");
                                    let proxy = proxy.clone();
                                    thread::spawn(move || {
                                        if wait_for_port(ZENOHD_PORT, PORT_WAIT_TIMEOUT) {
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
                                }
                                Err(e) => {
                                    let msg = format!("Failed to start zenohd: {}", e);
                                    rfd::MessageDialog::new()
                                        .set_title("Zenoh Router Start Failed")
                                        .set_description(&msg)
                                        .set_level(rfd::MessageLevel::Error)
                                        .show();
                                }
                            }
                        }
                    } else if menu_event.id == zenohd_quit_id {
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
                        }
                    } else if menu_event.id == phoenix_run_id {
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
                                            if wait_for_port(PHOENIX_SERVER_PORT, PORT_WAIT_TIMEOUT) {
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
                                    }
                                }
                            } else {
                                rfd::MessageDialog::new()
                                    .set_title("Phoenix Server Start Failed")
                                    .set_description("mix.exs not found. Run the launcher from the project directory.")
                                    .set_level(rfd::MessageLevel::Error)
                                    .show();
                            }
                        }
                    } else if menu_event.id == phoenix_quit_id {
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
                        }
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
                    zenohd_submenu.set_text("Zenoh Router : OFF");
                }
                // Quit 完了後の遅延 Ready 受信は無視する。cancelled を false に戻すのは
                // 次回 Run に備えてのリセットのみ。他に副作用なし。
                UserEvent::ZenohdReady => {
                    if *zenohd_starting_cancelled.borrow() {
                        *zenohd_starting_cancelled.borrow_mut() = false;
                    } else {
                        zenohd_submenu.set_text("Zenoh Router : ON");
                    }
                }
                UserEvent::ZenohdStartFailed(msg) => {
                    if *zenohd_starting_cancelled.borrow() {
                        *zenohd_starting_cancelled.borrow_mut() = false;
                    } else {
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
                        rfd::MessageDialog::new()
                            .set_title("Zenoh Router Start Failed")
                            .set_description(&msg)
                            .set_level(rfd::MessageLevel::Error)
                            .show();
                    }
                }
                // QuitComplete: 同上（zenohd と同様の整合性保証）
                UserEvent::PhoenixServerQuitComplete => {
                    phoenix_submenu.set_text("Phoenix Server : OFF");
                }
                // Ready: zenohd と同様（Quit 完了後の遅延 Ready を無視し、cancelled をリセット）
                UserEvent::PhoenixServerReady => {
                    if *phoenix_starting_cancelled.borrow() {
                        *phoenix_starting_cancelled.borrow_mut() = false;
                    } else {
                        phoenix_submenu.set_text("Phoenix Server : ON");
                    }
                }
                UserEvent::PhoenixServerStartFailed(msg) => {
                    if *phoenix_starting_cancelled.borrow() {
                        *phoenix_starting_cancelled.borrow_mut() = false;
                    } else {
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
                        rfd::MessageDialog::new()
                            .set_title("Phoenix Server Start Failed")
                            .set_description(&msg)
                            .set_level(rfd::MessageLevel::Error)
                            .show();
                    }
                }
                // 将来の拡張用（クリック・ダブルクリックなどの区別など）
                UserEvent::TrayIcon(event) => {
                    let _ = event;
                }
            }
        }
    });
}
