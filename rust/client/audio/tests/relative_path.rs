//! `AssetLoader::load_bytes_relative_path` の検証ルールと読み込みのスモーク。

use audio::AssetLoader;
use std::path::PathBuf;

#[test]
fn rejects_non_assets_prefix_and_parent_dir() {
    let loader = AssetLoader::with_base_path(".");
    assert!(loader.load_bytes_relative_path("etc/passwd").is_none());
    assert!(loader.load_bytes_relative_path("assets/../Cargo.toml").is_none());
    assert!(loader.load_bytes_relative_path("assets\\audio\\hit.wav").is_none());
}

#[test]
fn reads_player_hurt_from_repo_root() {
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let loader = AssetLoader::with_base_path(&repo);
    let bytes = loader
        .load_bytes_relative_path("assets/audio/player_hurt.wav")
        .expect("repo fixture wav");
    assert!(bytes.len() > 100);
}
