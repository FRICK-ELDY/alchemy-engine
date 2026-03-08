//! Phase 2: zenohd Run / Quit + ポート確認
//!
//! トレイアイコン表示、メニューから zenohd を起動・終了。
//! ポート 7447 で待ち受けを確認して成功/失敗を判定。

use std::cell::RefCell;
use std::net::{SocketAddr, TcpStream};
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

/// zenohd は tcp/[::]:7447 で待ち受けるため、IPv4 と IPv6 の両方を試す。
const PORT_CHECK_ADDRESSES: &[&str] = &["127.0.0.1", "[::1]"];

/// zenohd がポートに bind するまでの初回待機
const PORT_INITIAL_DELAY: Duration = Duration::from_millis(500);

/// ポートが応答するまで待機する。
///
/// - 成功: `true` を返す（いずれかのアドレスに接続できた場合）
/// - タイムアウト: `false` を返す
/// - 接続試行中の I/O エラーは無視してリトライを続ける
fn wait_for_port(port: u16, timeout: Duration) -> bool {
    let addrs: Vec<SocketAddr> = PORT_CHECK_ADDRESSES
        .iter()
        .filter_map(|host| {
            format!("{}:{}", host, port).parse().map_or_else(
                |_| {
                    eprintln!("[launcher] Invalid port check address: {}:{}", host, port);
                    None
                },
                Some,
            )
        })
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

fn main() {
    let event_loop = EventLoopBuilder::with_user_event().build();
    let proxy = event_loop.create_proxy();

    enum UserEvent {
        TrayIcon(TrayIconEvent),
        Menu(MenuEvent),
        /// バックグラウンドスレッドでの zenohd 終了完了
        ZenohdQuitComplete,
        /// ポート 7447 が応答した（起動成功）
        ZenohdReady,
        /// 起動失敗（タイムアウトなど）
        ZenohdStartFailed(String),
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
    let quit_id = MenuId::new("quit");

    // 設計書 2.1 では「zenohd Run」「zenohd Quit」。UI では「Zenoh Router」で分かりやすく表示。
    let zenohd_run_item = MenuItem::with_id(zenohd_run_id.clone(), "Run", true, None);
    let zenohd_quit_item = MenuItem::with_id(zenohd_quit_id.clone(), "Quit", true, None);

    let zenohd_submenu = Rc::new(Submenu::new("Zenoh Router : OFF", true));
    zenohd_submenu.append(&zenohd_run_item).expect("Failed to append run");
    zenohd_submenu.append(&zenohd_quit_item).expect("Failed to append quit");

    let quit_item = MenuItem::with_id(quit_id.clone(), "Quit", true, None);

    let menu = Menu::new();
    menu.append(zenohd_submenu.as_ref()).expect("Failed to append submenu");
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
    // Quit が「起動中」中に押された場合、ZenohdReady / ZenohdStartFailed の処理をスキップする
    let zenohd_starting_cancelled = Rc::new(RefCell::new(false));

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
                            // 即座に UI を更新（スレッド完了を待たない）
                            zenohd_submenu.set_text("Zenoh Router : OFF");
                        }
                    } else if menu_event.id == quit_id {
                        let mut child_opt = zenohd_child.borrow_mut();
                        if let Some(child) = child_opt.take() {
                            terminate_zenohd_sync(child, &zenohd_submenu);
                        }
                        *control_flow = ControlFlow::Exit;
                    }
                }
                UserEvent::ZenohdQuitComplete => {
                    // バックグラウンド終了完了。try_wait 検知とスレッド完了の競合で
                    // 二重更新の可能性はあるが、同じ値なので問題なし。
                    zenohd_submenu.set_text("Zenoh Router : OFF");
                }
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
                        // Quit で既に child は取得・終了済み。メニュー更新とダイアログをスキップ
                    } else {
                        let mut child_opt = zenohd_child.borrow_mut();
                        if let Some(mut child) = child_opt.take() {
                            let pid = child.id();
                            if let Err(e) = kill_tree(pid) {
                                eprintln!("zenohd の終了に失敗しました: {}", e);
                            }
                            if let Err(e) = child.wait() {
                                eprintln!("zenohd wait エラー: {}", e);
                            }
                        }
                        zenohd_submenu.set_text("Zenoh Router : OFF");
                        rfd::MessageDialog::new()
                            .set_title("Zenoh Router Start Failed")
                            .set_description(&msg)
                            .set_level(rfd::MessageLevel::Error)
                            .show();
                    }
                }
                UserEvent::TrayIcon(event) => {
                    let _ = event;
                }
            }
        }
    });
}
