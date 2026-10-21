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
//!   ASSETS_ID - コンテンツ別サブディレクトリ（例: bullet_hell_3d）で assets/{id}/ を参照
//!   ALCHEMY_AUTH_URL - alchemy-auth のベース URL（既定 http://localhost:4002。
//!                      localhost 以外は https 必須）
//!   ALCHEMY_ENGINE_URL - world-server の HTTP（既定 http://127.0.0.1:4000。
//!                        RoomToken の取得先。localhost 以外は https 必須）

use audio::{start_audio_thread, AssetLoader};
use network::{NetworkRenderBridge, RoomTokenFetch};
use render::window::{RendererInit, WindowConfig};
use shared::display::{SCREEN_HEIGHT, SCREEN_WIDTH};
use std::sync::Arc;
use system_ui::auth_client::{default_engine_base_url, AuthClient, ENGINE_URL_ENV};
use system_ui::SystemUi;
use window::run_desktop_loop_with_system_ui;

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

    let audio_tx = start_audio_thread(loader.clone());
    let bridge = NetworkRenderBridge::new_with_room_auth(
        connect_str,
        &room_id,
        Some(audio_tx),
        Some(room_token_fetcher()),
    )?;

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

    run_desktop_loop_with_system_ui(bridge, config, build_system_ui())
}

fn room_token_fetcher() -> RoomTokenFetch {
    let client = AuthClient::from_env().ok();
    let engine = std::env::var(ENGINE_URL_ENV).unwrap_or_else(|_| default_engine_base_url());
    Arc::new(move |access_token, room_id| {
        let client = client
            .clone()
            .ok_or_else(|| "auth client is not configured".to_string())?;
        client
            .issue_room_token(&engine, access_token, room_id)
            .map_err(|e| e.to_string())
    })
}

/// システムメニューを構成する。auth URL が不正でもクライアント自体は起動し、
/// ログイン/登録フォームだけが "not configured" 表示になる。
fn build_system_ui() -> SystemUi {
    let mut system_ui = SystemUi::new();
    match AuthClient::from_env() {
        Ok(client) => {
            log::info!("auth service: {}", client.base_url());
            system_ui.set_auth_client(client);
        }
        Err(e) => log::warn!("auth client disabled: {e}"),
    }
    system_ui
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
