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
