//! Path: native/game_audio/src/audio.rs
//! Summary: BGM・SE 管理（rodio）+ コマンド駆動オーディオスレッド
//!
//! 音声データは [AssetLoader](crate::asset::AssetLoader) 経由で取得すること（Single Source of Truth）。

use crate::asset::{AssetId, AssetLoader};
use rodio::{Decoder, OutputStream, OutputStreamBuilder, Sink, Source};
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;

#[allow(dead_code)]
pub struct AudioManager {
    _stream:  OutputStream,
    bgm_sink: Sink,
}

impl AudioManager {
    pub fn new() -> Option<Self> {
        let stream = OutputStreamBuilder::open_default_stream().ok()?;
        let bgm_sink = Sink::connect_new(&stream.mixer());
        Some(Self { _stream: stream, bgm_sink })
    }

    pub fn play_bgm(&self, bytes: Vec<u8>) {
        if !self.bgm_sink.empty() {
            return;
        }
        let cursor = std::io::Cursor::new(bytes);
        if let Ok(source) = Decoder::new(cursor) {
            self.bgm_sink.append(source.buffered().repeat_infinite());
        }
    }

    pub fn pause_bgm(&self) {
        self.bgm_sink.pause();
    }

    pub fn resume_bgm(&self) {
        self.bgm_sink.play();
    }

    pub fn set_bgm_volume(&self, volume: f32) {
        self.bgm_sink.set_volume(volume.clamp(0.0, 1.0));
    }

    pub fn play_se(&self, bytes: Vec<u8>) {
        self.play_se_with_volume(bytes, 1.0);
    }

    pub fn play_se_with_volume(&self, bytes: Vec<u8>, volume: f32) {
        let cursor = std::io::Cursor::new(bytes);
        if let Ok(source) = Decoder::new(cursor) {
            let sink = Sink::connect_new(&self._stream.mixer());
            sink.set_volume(volume.clamp(0.0, 1.0));
            sink.append(source);
            sink.detach();
        }
    }
}

/// Audio スレッドに送るコマンド。
///
/// World を直接更新せず、音再生要求だけをキューで渡すための境界。
#[derive(Debug, Clone)]
pub enum AudioCommand {
    PlayBgm,
    PauseBgm,
    ResumeBgm,
    SetBgmVolume(f32),
    PlaySe(AssetId),
    PlaySeWithVolume(AssetId, f32),
    Shutdown,
}

/// Audio コマンド送信ハンドル（クローン可能）。
#[derive(Clone)]
pub struct AudioCommandSender {
    tx: Sender<AudioCommand>,
}

impl AudioCommandSender {
    fn send(&self, command: AudioCommand) {
        let _ = self.tx.send(command);
    }

    pub fn play_bgm(&self) { self.send(AudioCommand::PlayBgm); }
    pub fn pause_bgm(&self) { self.send(AudioCommand::PauseBgm); }
    pub fn resume_bgm(&self) { self.send(AudioCommand::ResumeBgm); }
    pub fn set_bgm_volume(&self, volume: f32) { self.send(AudioCommand::SetBgmVolume(volume)); }
    pub fn play_se(&self, id: AssetId) { self.send(AudioCommand::PlaySe(id)); }
    pub fn play_se_with_volume(&self, id: AssetId, volume: f32) { self.send(AudioCommand::PlaySeWithVolume(id, volume)); }
    pub fn shutdown(&self) { self.send(AudioCommand::Shutdown); }
}

/// Audio ワーカーを起動し、コマンド送信ハンドルを返す。
///
/// 失敗時でもハンドルは返す（送信は無視される）。呼び出し側を止めない設計。
pub fn start_audio_thread(loader: AssetLoader) -> AudioCommandSender {
    let (tx, rx) = mpsc::channel::<AudioCommand>();
    let thread_tx = tx.clone();
    let _ = thread::Builder::new()
        .name("audio-thread".to_string())
        .spawn(move || run_audio_loop(rx, loader));
    AudioCommandSender { tx: thread_tx }
}

fn run_audio_loop(rx: Receiver<AudioCommand>, loader: AssetLoader) {
    let audio = AudioManager::new();
    if audio.is_none() {
        log::warn!("Audio output device is unavailable; audio commands will be dropped");
    }

    while let Ok(command) = rx.recv() {
        match command {
            AudioCommand::PlayBgm => {
                if let Some(audio) = &audio { audio.play_bgm(loader.load_audio(AssetId::Bgm)); }
            }
            AudioCommand::PauseBgm => {
                if let Some(audio) = &audio { audio.pause_bgm(); }
            }
            AudioCommand::ResumeBgm => {
                if let Some(audio) = &audio { audio.resume_bgm(); }
            }
            AudioCommand::SetBgmVolume(volume) => {
                if let Some(audio) = &audio { audio.set_bgm_volume(volume); }
            }
            AudioCommand::PlaySe(id) => {
                if let Some(audio) = &audio { audio.play_se(loader.load_audio(id)); }
            }
            AudioCommand::PlaySeWithVolume(id, volume) => {
                if let Some(audio) = &audio { audio.play_se_with_volume(loader.load_audio(id), volume); }
            }
            AudioCommand::Shutdown => break,
        }
    }
}
