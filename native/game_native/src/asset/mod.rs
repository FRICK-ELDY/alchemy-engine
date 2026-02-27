//! Path: native/game_native/src/asset/mod.rs
//! Summary: アセット ID マッピング・実行時ロード・埋め込みフォールバック
//! 1.7.3: game_window から game_native に移動。
//!
//! G3: アセット管理システム。アセット ID → パス のマッピング、実行時ロード、
//! 埋め込みフォールバックを提供。設計: `docs/06_system_design/ASSET_MANAGEMENT.md`
//! アセットパスは環境変数 GAME_ASSETS_PATH と GAME_ASSETS_ID で解決する。

use std::path::Path;

/// アセット ID とパスの定義を1箇所に集約（single source of truth）
macro_rules! define_assets {
    ($($id:ident => $path:literal),* $(,)?) => {
        /// アセットを一意に識別する ID
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        #[allow(dead_code)] // Phase 2 で音声ロードに使用予定
        pub enum AssetId {
            $($id,)*
        }

        impl AssetId {
            /// デフォルトの相対パス（プロジェクトルート基準）
            pub fn default_path(&self) -> &'static str {
                match self {
                    $(AssetId::$id => $path,)*
                }
            }
        }

        fn load_asset_embedded(id: AssetId) -> Vec<u8> {
            match id {
                $(AssetId::$id => include_bytes!(concat!("../../../../", $path)).to_vec(),)*
            }
        }
    };
}

define_assets! {
    SpriteAtlas => "assets/sprites/atlas.png",
    Bgm => "assets/audio/bgm.wav",
    HitSfx => "assets/audio/hit.wav",
    DeathSfx => "assets/audio/death.wav",
    LevelUpSfx => "assets/audio/level_up.wav",
    PlayerHurtSfx => "assets/audio/player_hurt.wav",
    ItemPickupSfx => "assets/audio/item_pickup.wav",
}

/// アセットのロードを行う。実行時ロード（ファイル存在時）＋埋め込みフォールバック。
/// 1.4.8: ゲーム別アセットパス — game_assets_id により assets/{id}/ を参照可能。
pub struct AssetLoader {
    /// ベースパス（プロジェクトルート相当）。None の場合はカレントディレクトリまたは埋め込みを使用
    base_path: Option<std::path::PathBuf>,
    /// ゲーム ID（例: "vampire_survivor"）。指定時は assets/{id}/sprites/ 等を優先参照
    game_assets_id: Option<String>,
}

impl Default for AssetLoader {
    fn default() -> Self {
        Self::new()
    }
}

impl AssetLoader {
    fn base_path_from_env() -> Option<std::path::PathBuf> {
        std::env::var("GAME_ASSETS_PATH")
            .ok()
            .filter(|s| !s.is_empty())
            .map(std::path::PathBuf::from)
    }

    /// 環境変数 `GAME_ASSETS_PATH` と `GAME_ASSETS_ID` から作成する。
    /// `GAME_ASSETS_ID` が設定されていれば、assets/{id}/ を優先して参照する。
    pub fn new() -> Self {
        let game_assets_id = std::env::var("GAME_ASSETS_ID")
            .ok()
            .filter(|s| !s.is_empty());
        Self {
            base_path: Self::base_path_from_env(),
            game_assets_id,
        }
    }

    /// ゲーム ID を指定して作成（1.4.8: with_game_assets）。
    /// 例: `AssetLoader::with_game_assets("vampire_survivor")` → assets/vampire_survivor/ を参照
    #[allow(dead_code)] // 明示指定用。通常は new() が GAME_ASSETS_ID を読む
    pub fn with_game_assets(game_id: &str) -> Self {
        let game_assets_id = if game_id.is_empty() {
            None
        } else {
            Some(game_id.to_string())
        };
        Self {
            base_path: Self::base_path_from_env(),
            game_assets_id,
        }
    }

    /// カスタムベースパスを指定して作成（Elixir からのパス指定用・将来拡張）
    #[allow(dead_code)]
    pub fn with_base_path<P: AsRef<Path>>(path: P) -> Self {
        Self {
            base_path: Some(path.as_ref().to_path_buf()),
            game_assets_id: None,
        }
    }

    /// default_path から game_assets_id を挿入したパスを生成。
    /// "assets/sprites/atlas.png" + "vampire_survivor" → "assets/vampire_survivor/sprites/atlas.png"
    fn game_specific_path(&self, default_path: &str) -> Option<String> {
        let id = self.game_assets_id.as_ref()?;
        if let Some(rest) = default_path.strip_prefix("assets/") {
            Some(format!("assets/{}/{}", id, rest))
        } else {
            None
        }
    }

    /// アセットのバイト列をロードする。
    /// 1. game_assets_id 指定時: assets/{id}/... を優先
    /// 2. base_path + 相対パス でファイルが存在すればそこから読み込む
    /// 3. カレントディレクトリからの相対パスで存在すれば読み込む
    /// 4. どれも失敗すればコンパイル時埋め込みデータを使用
    pub fn load_bytes(&self, id: AssetId) -> Vec<u8> {
        let default_path = id.default_path();

        let mut paths_to_try: Vec<std::path::PathBuf> = Vec::new();

        // 1. ゲーム別パスを試行
        if let Some(game_path_str) = self.game_specific_path(default_path) {
            if let Some(base) = &self.base_path {
                paths_to_try.push(base.join(&game_path_str));
            }
            paths_to_try.push(game_path_str.into());
        }

        // 2. ベースパス + デフォルト相対パス
        if let Some(base) = &self.base_path {
            paths_to_try.push(base.join(default_path));
        }

        // 3. カレントディレクトリからの相対パス
        paths_to_try.push(default_path.into());

        for path in paths_to_try {
            if let Ok(bytes) = std::fs::read(&path) {
                return bytes;
            }
        }

        // 4. 埋め込みフォールバック
        self.load_embedded(id)
    }

    /// スプライトアトラスのバイト列をロード（利便性のためのショートカット）
    pub fn load_sprite_atlas(&self) -> Vec<u8> {
        self.load_bytes(AssetId::SpriteAtlas)
    }

    /// 音声アセットのバイト列をロード（AudioManager 連携用）
    #[allow(dead_code)]
    pub fn load_audio(&self, id: AssetId) -> Vec<u8> {
        self.load_bytes(id)
    }

    /// コンパイル時埋め込みデータ（ファイルが存在しない場合のフォールバック）
    fn load_embedded(&self, id: AssetId) -> Vec<u8> {
        load_asset_embedded(id)
    }
}
