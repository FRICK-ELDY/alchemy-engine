//! Phase 1: zenohd Run / Quit
//!
//! トレイアイコン表示、メニューから zenohd を起動・終了。
//! ポート確認は Phase 2 で対応。

use std::cell::RefCell;
use std::process::{Child, Command};
use std::rc::Rc;
use std::thread;
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use kill_tree::blocking::kill_tree;
use tray_icon::{
    menu::{Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem, Submenu},
    Icon, TrayIconBuilder, TrayIconEvent,
};

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
                                    zenohd_submenu.set_text("Zenoh Router : ON");
                                }
                                Err(e) => {
                                    eprintln!("zenohd の起動に失敗しました: {}", e);
                                    // TODO: トレイアプリではコンソールがなく気づきにくい。トーストやダイアログ通知を検討。
                                }
                            }
                        }
                    } else if menu_event.id == zenohd_quit_id {
                        let mut child_opt = zenohd_child.borrow_mut();
                        if let Some(mut child) = child_opt.take() {
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
                UserEvent::TrayIcon(event) => {
                    let _ = event;
                }
            }
        }
    });
}
