use crate::world::GameWorldInner;
use game_core::entity_params::{
    WEAPON_ID_AXE, WEAPON_ID_CROSS, WEAPON_ID_FIREBALL, WEAPON_ID_GARLIC, WEAPON_ID_LIGHTNING,
    WEAPON_ID_MAGIC_WAND, WEAPON_ID_WHIP,
};

/// 1.7.5: レベルアップ時の武器選択肢を計算（未所持優先 → 低レベル順、Lv8 除外）
pub(crate) fn compute_weapon_choices(w: &GameWorldInner) -> Vec<String> {
    const ALL: &[(&str, u8)] = &[
        ("magic_wand", WEAPON_ID_MAGIC_WAND),
        ("axe", WEAPON_ID_AXE),
        ("cross", WEAPON_ID_CROSS),
        ("whip", WEAPON_ID_WHIP),
        ("fireball", WEAPON_ID_FIREBALL),
        ("lightning", WEAPON_ID_LIGHTNING),
        ("garlic", WEAPON_ID_GARLIC),
    ];

    let mut choices: Vec<(i32, String)> = ALL
        .iter()
        .filter_map(|(name, wid)| {
            let lv = w
                .weapon_slots
                .iter()
                .find(|s| s.kind_id == *wid)
                .map(|s| s.level)
                .unwrap_or(0);
            if lv >= 8 {
                return None;
            }
            let sort_key = if lv == 0 { -1i32 } else { lv as i32 };
            Some((sort_key, (*name).to_string()))
        })
        .collect();

    choices.sort_by_key(|(k, _)| *k);
    choices.into_iter().take(3).map(|(_, n)| n).collect()
}
