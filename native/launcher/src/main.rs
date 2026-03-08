//! Phase 0: ランチャーの起動と終了確認
//!
//! トレイアイコン表示、右クリックでメニュー、「Quit」で終了。

use tao::event_loop::{ControlFlow, EventLoopBuilder};
use tray_icon::{
    menu::{Menu, MenuEvent, MenuId, MenuItem},
    Icon, TrayIconBuilder, TrayIconEvent,
};

/// 16x16 のプレースホルダーアイコン（紫系）
fn create_icon() -> Icon {
    let size: u32 = 16;
    let mut rgba = Vec::with_capacity((size * size * 4) as usize);
    for y in 0..size {
        for x in 0..size {
            let r = 0x4B;
            let g = 0x27;
            let b = 0x5F;
            let a = if (x > 1 && x < 14) && (y > 1 && y < 14) {
                0xFF
            } else {
                0x80
            };
            rgba.extend_from_slice(&[r, g, b, a]);
        }
    }
    Icon::from_rgba(rgba, size, size).expect("Failed to create icon")
}

fn main() {
    let event_loop = EventLoopBuilder::with_user_event().build();
    let proxy = event_loop.create_proxy();

    enum UserEvent {
        TrayIcon(TrayIconEvent),
        Menu(MenuEvent),
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

    let quit_id = MenuId::new("quit");
    let quit_item = MenuItem::with_id(quit_id.clone(), "Quit", true, None);
    let menu = Menu::new();
    menu.append(&quit_item).expect("Failed to append menu item");

    let _tray_icon = TrayIconBuilder::new()
        .with_menu(Box::new(menu))
        .with_tooltip("AlchemyEngine")
        .with_icon(create_icon())
        .build()
        .expect("Failed to create tray icon");

    event_loop.run(move |event, _, control_flow| {
        // Phase 0: Poll で簡易実装。将来は Wait/WaitUntil に切り替えてアイドル時の負荷を下げることを検討。
        *control_flow = ControlFlow::Poll;

        if let tao::event::Event::UserEvent(user_event) = event {
            match user_event {
                UserEvent::Menu(menu_event) => {
                    if menu_event.id == quit_id {
                        *control_flow = ControlFlow::Exit;
                    }
                }
                UserEvent::TrayIcon(event) => {
                    // Phase 0 ではトレイアイコンクリック時の特別な処理は不要
                    let _ = event;
                }
            }
        }
    });
}
