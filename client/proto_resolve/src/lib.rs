//! Resolve `alchemy-protocol` `proto/` for `build.rs`.
//!
//! 1. `PROTO_ROOT` if set (must be a directory containing `.proto` files)
//! 2. Otherwise clone/fetch [`PROTOCOL_PIN`](../PROTOCOL_PIN) into
//!    `<repo>/.proto-cache/alchemy-protocol-<tag>/` (R2)

use std::fs::{self, OpenOptions};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct ProtocolPin {
    pub tag: String,
    pub sha: String,
    pub url: String,
}

/// Resolve the directory that contains top-level `.proto` files (e.g. `render_frame.proto`).
pub fn resolve_proto_root() -> Result<PathBuf, Box<dyn std::error::Error>> {
    println!("cargo:rerun-if-env-changed=PROTO_ROOT");

    if let Ok(root) = std::env::var("PROTO_ROOT") {
        let p = PathBuf::from(root);
        ensure_proto_dir(&p)?;
        return Ok(p);
    }

    let repo_root = find_repo_root()?;
    let pin_path = repo_root.join("PROTOCOL_PIN");
    println!("cargo:rerun-if-changed={}", pin_path.display());

    let pin = read_pin(&pin_path)?;
    let cache_root = repo_root.join(".proto-cache");
    let cache_repo = cache_root.join(format!("alchemy-protocol-{}", pin.tag));
    let proto_dir = cache_repo.join("proto");

    if cache_ready(&cache_repo, &proto_dir, &pin.sha)? {
        return Ok(proto_dir);
    }

    ensure_cache_with_lock(&cache_root, &cache_repo, &proto_dir, &pin)?;
    ensure_proto_dir(&proto_dir)?;
    Ok(proto_dir)
}

fn ensure_cache_with_lock(
    cache_root: &Path,
    cache_repo: &Path,
    proto_dir: &Path,
    pin: &ProtocolPin,
) -> Result<(), Box<dyn std::error::Error>> {
    fs::create_dir_all(cache_root)?;
    let lock_path = cache_root.join(format!(".lock-{}", pin.tag));

    for _ in 0..100 {
        if cache_ready(cache_repo, proto_dir, &pin.sha)? {
            return Ok(());
        }

        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&lock_path)
        {
            Ok(_lock_file) => {
                let result = (|| {
                    if cache_ready(cache_repo, proto_dir, &pin.sha)? {
                        return Ok(());
                    }
                    if cache_repo.exists() {
                        let _ = fs::remove_dir_all(cache_repo);
                    }
                    git_clone(pin, cache_repo)?;
                    let head = git_rev_parse(cache_repo)?;
                    if !head_matches(&head, &pin.sha) {
                        return Err(format!(
                            "PROTOCOL_PIN sha mismatch: expected {}..., got {} (tag {})",
                            &pin.sha[..pin.sha.len().min(12)],
                            head,
                            pin.tag
                        )
                        .into());
                    }
                    Ok(())
                })();
                let _ = fs::remove_file(&lock_path);
                return result;
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                thread::sleep(Duration::from_millis(200));
            }
            Err(e) => return Err(e.into()),
        }
    }

    Err(format!(
        "timed out waiting for proto cache lock. If no other build is running, delete {}",
        lock_path.display()
    )
    .into())
}

fn cache_ready(
    cache_repo: &Path,
    proto_dir: &Path,
    pin_sha: &str,
) -> Result<bool, Box<dyn std::error::Error>> {
    if !proto_dir.is_dir() {
        return Ok(false);
    }
    match git_rev_parse(cache_repo) {
        Ok(head) => Ok(head_matches(&head, pin_sha)),
        Err(_) => Ok(false),
    }
}

fn ensure_proto_dir(p: &Path) -> Result<(), Box<dyn std::error::Error>> {
    if !p.is_dir() {
        return Err(format!(
            "proto directory missing: {} (set PROTO_ROOT or allow git fetch via PROTOCOL_PIN)",
            p.display()
        )
        .into());
    }
    Ok(())
}

fn find_repo_root() -> Result<PathBuf, Box<dyn std::error::Error>> {
    let mut dir = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR")?);
    for _ in 0..8 {
        // world-server: PROTOCOL_PIN + mix.exs / alchemy-client: PROTOCOL_PIN + workspace Cargo.toml
        let has_pin = dir.join("PROTOCOL_PIN").is_file();
        let has_mix = dir.join("mix.exs").is_file();
        let has_ws = dir.join("Cargo.toml").is_file();
        if has_pin && (has_mix || has_ws) {
            return Ok(dir);
        }
        if !dir.pop() {
            break;
        }
    }
    Err(
        "could not find repo root (PROTOCOL_PIN + mix.exs or Cargo.toml) from CARGO_MANIFEST_DIR"
            .into(),
    )
}

fn read_pin(path: &Path) -> Result<ProtocolPin, Box<dyn std::error::Error>> {
    let text = fs::read_to_string(path)?;
    let mut tag = None;
    let mut sha = None;
    let mut url = None;
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else {
            continue;
        };
        match k.trim() {
            "tag" => tag = Some(v.trim().to_string()),
            "sha" => sha = Some(v.trim().to_string()),
            "url" => url = Some(v.trim().to_string()),
            _ => {}
        }
    }
    Ok(ProtocolPin {
        tag: nonempty(tag.ok_or("PROTOCOL_PIN missing tag=")?, "tag")?,
        sha: nonempty(sha.ok_or("PROTOCOL_PIN missing sha=")?, "sha")?,
        url: nonempty(url.ok_or("PROTOCOL_PIN missing url=")?, "url")?,
    })
}

fn nonempty(value: String, key: &str) -> Result<String, Box<dyn std::error::Error>> {
    if value.is_empty() {
        return Err(format!("PROTOCOL_PIN {key}= must not be empty").into());
    }
    Ok(value)
}

fn git_clone(pin: &ProtocolPin, dest: &Path) -> Result<(), Box<dyn std::error::Error>> {
    eprintln!(
        "[proto_resolve] fetching {} @ {} into {}",
        pin.url,
        pin.tag,
        dest.display()
    );
    let status = Command::new("git")
        .args(["clone", "--depth", "1", "--branch", &pin.tag, &pin.url])
        .arg(dest)
        .status()?;
    if !status.success() {
        return Err(format!("git clone failed for {} @ {}", pin.url, pin.tag).into());
    }
    Ok(())
}

fn git_rev_parse(repo: &Path) -> Result<String, Box<dyn std::error::Error>> {
    let out = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .current_dir(repo)
        .output()?;
    if !out.status.success() {
        return Err("git rev-parse HEAD failed".into());
    }
    Ok(String::from_utf8(out.stdout)?.trim().to_string())
}

fn head_matches(head: &str, pin_sha: &str) -> bool {
    let head = head.trim().to_ascii_lowercase();
    let pin = pin_sha.trim().to_ascii_lowercase();
    if pin.is_empty() {
        return false;
    }
    head == pin || head.starts_with(&pin) || pin.starts_with(&head)
}
