//! app: 統合層・デスクトップエントリ
//!
//! Zenoh 経由でサーバーに接続するデスクトップクライアント（Windows/Linux/macOS）
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
//!
//! 使用方法:
//!   app [--connect CONNECT] [--room ROOM_ID] [--assets PATH]
//!
//! 環境変数:
//!   ZENOH_CONNECT - 接続先（例: tcp/127.0.0.1:7447）。未指定時は zenoh のデフォルト
//!   ASSETS_PATH - アセットルート（未指定時はカレントディレクトリ）
//!   ASSETS_ID - コンテンツ別サブディレクトリ（例: vampire_survivor）で assets/{id}/ を参照

use audio::AssetLoader;
use network::NetworkRenderBridge;
use nif::physics::constants::{SCREEN_HEIGHT, SCREEN_WIDTH};
use render::window::{RendererInit, WindowConfig};
use window::run_desktop_loop;

fn main() -> Result<(), String> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let (connect, room_id, assets_path) = parse_args();
    log::info!("connect={connect:?} room={room_id} assets={assets_path:?}");

    let connect_str = connect.as_deref().unwrap_or("");
    if !connect_str.is_empty() {
        std::env::set_var("ZENOH_CONNECT", connect_str);
    }
    if let Some(ref p) = assets_path {
        std::env::set_var("ASSETS_PATH", p);
    }

    let loader = loader_for_assets(assets_path.as_deref());
    let atlas_png = load_atlas(&loader);
    let (sprite_wgsl, mesh_wgsl) = load_shaders(assets_path.as_deref());

    let bridge = NetworkRenderBridge::new(connect_str, &room_id)?;

    let config = WindowConfig {
        title: format!("Alchemy Client — room {}", room_id),
        width: SCREEN_WIDTH as u32,
        height: SCREEN_HEIGHT as u32,
        renderer_init: RendererInit {
            atlas_png,
            sprite_wgsl,
            mesh_wgsl,
        },
    };

    run_desktop_loop(bridge, config)
}

fn parse_args() -> (Option<String>, String, Option<String>) {
    let args: Vec<String> = std::env::args().collect();
    let mut connect = None;
    let mut room_id = String::from("main");
    let mut assets_path = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--connect" | "-c" => {
                i += 1;
                if i < args.len() {
                    connect = Some(args[i].clone());
                }
                i += 1;
            }
            "--room" | "-r" => {
                i += 1;
                if i < args.len() {
                    room_id = args[i].clone();
                }
                i += 1;
            }
            "--assets" | "-a" => {
                i += 1;
                if i < args.len() {
                    assets_path = Some(args[i].clone());
                }
                i += 1;
            }
            _ => i += 1,
        }
    }

    if connect.is_none() {
        connect = std::env::var("ZENOH_CONNECT").ok();
    }

    (connect, room_id, assets_path)
}

fn loader_for_assets(assets_path: Option<&str>) -> AssetLoader {
    match assets_path {
        Some(p) => AssetLoader::with_base_path(p),
        None => AssetLoader::new(),
    }
}

fn load_atlas(loader: &AssetLoader) -> Vec<u8> {
    loader.load_sprite_atlas()
}

fn load_shaders(assets_path: Option<&str>) -> (Option<String>, Option<String>) {
    let try_load = |base: Option<&str>, name: &str| -> Option<String> {
        if let Some(base) = base {
            let path = std::path::Path::new(base).join("shaders").join(name);
            if let Ok(s) = std::fs::read_to_string(&path) {
                return Some(s);
            }
        }
        let fallback = std::path::Path::new("assets/shaders").join(name);
        std::fs::read_to_string(&fallback).ok()
    };
    let sprite = try_load(assets_path, "sprite.wgsl");
    let mesh = try_load(assets_path, "mesh.wgsl");
    (sprite, mesh)
}
