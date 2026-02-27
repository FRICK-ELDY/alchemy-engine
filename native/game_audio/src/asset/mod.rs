//! Path: native/game_audio/src/asset/mod.rs
//! Summary: アセット ID マッピング・実行時ロード・埋め込みフォールバック

use std::path::Path;

/// アセット ID とパスの定義を1箇所に集約（single source of truth）
macro_rules! define_assets {
    ($($id:ident => $path:literal),* $(,)?) => {
        /// アセットを一意に識別する ID
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        #[allow(dead_code)]
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
    SpriteAtlas    => "assets/sprites/atlas.png",
    Bgm            => "assets/audio/bgm.wav",
    HitSfx         => "assets/audio/hit.wav",
    DeathSfx       => "assets/audio/death.wav",
    LevelUpSfx     => "assets/audio/level_up.wav",
    PlayerHurtSfx  => "assets/audio/player_hurt.wav",
    ItemPickupSfx  => "assets/audio/item_pickup.wav",
}

/// アセットのロードを行う。実行時ロード（ファイル存在時）＋埋め込みフォールバック。
pub struct AssetLoader {
    base_path: Option<std::path::PathBuf>,
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
    pub fn new() -> Self {
        let game_assets_id = std::env::var("GAME_ASSETS_ID")
            .ok()
            .filter(|s| !s.is_empty());
        Self {
            base_path: Self::base_path_from_env(),
            game_assets_id,
        }
    }

    #[allow(dead_code)]
    pub fn with_game_assets(game_id: &str) -> Self {
        let game_assets_id = if game_id.is_empty() { None } else { Some(game_id.to_string()) };
        Self { base_path: Self::base_path_from_env(), game_assets_id }
    }

    #[allow(dead_code)]
    pub fn with_base_path<P: AsRef<Path>>(path: P) -> Self {
        Self { base_path: Some(path.as_ref().to_path_buf()), game_assets_id: None }
    }

    fn game_specific_path(&self, default_path: &str) -> Option<String> {
        let id = self.game_assets_id.as_ref()?;
        if let Some(rest) = default_path.strip_prefix("assets/") {
            Some(format!("assets/{}/{}", id, rest))
        } else {
            None
        }
    }

    pub fn load_bytes(&self, id: AssetId) -> Vec<u8> {
        let default_path = id.default_path();
        let mut paths_to_try: Vec<std::path::PathBuf> = Vec::new();

        if let Some(game_path_str) = self.game_specific_path(default_path) {
            if let Some(base) = &self.base_path {
                paths_to_try.push(base.join(&game_path_str));
            }
            paths_to_try.push(game_path_str.into());
        }
        if let Some(base) = &self.base_path {
            paths_to_try.push(base.join(default_path));
        }
        paths_to_try.push(default_path.into());

        for path in paths_to_try {
            if let Ok(bytes) = std::fs::read(&path) {
                return bytes;
            }
        }
        self.load_embedded(id)
    }

    pub fn load_sprite_atlas(&self) -> Vec<u8> {
        self.load_bytes(AssetId::SpriteAtlas)
    }

    pub fn load_audio(&self, id: AssetId) -> Vec<u8> {
        self.load_bytes(id)
    }

    fn load_embedded(&self, id: AssetId) -> Vec<u8> {
        load_asset_embedded(id)
    }
}
