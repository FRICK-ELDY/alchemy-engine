//! クライアント側バリデーション（UX 用の先行チェック）。
//!
//! ルールは auth 側のサーバサイド検証（auth/lib/auth/accounts/user.ex）と
//! 同一にする。正はあくまで auth 側で、ここは即時フィードバック用。

/// パスワード複雑性のヒント（登録フォームに常時表示する）。
pub const PASSWORD_HINT: &str = "at least 8 characters, 1 digit, 1 lowercase, 1 uppercase";

/// Username: 3〜20 文字、英数字とアンダースコアのみ。
pub fn validate_username(username: &str) -> Result<(), &'static str> {
    let len = username.chars().count();
    if !(3..=20).contains(&len) {
        return Err("must be 3-20 characters");
    }
    if !username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return Err("only letters, digits, and underscores are allowed");
    }
    Ok(())
}

/// Email: `@` を含む簡易形式チェック（auth 側の ~r/^[^\s@]+@[^\s@]+$/ と同等）。
pub fn validate_email(email: &str) -> Result<(), &'static str> {
    let mut parts = email.split('@');
    let (Some(local), Some(domain), None) = (parts.next(), parts.next(), parts.next()) else {
        return Err("must be a valid email address");
    };
    if local.is_empty() || domain.is_empty() || email.chars().any(char::is_whitespace) {
        return Err("must be a valid email address");
    }
    Ok(())
}

/// Password: 8 文字以上、数字 1 以上、小文字 1 以上、大文字 1 以上。
pub fn validate_password(password: &str) -> Result<(), &'static str> {
    if password.chars().count() < 8 {
        return Err("must be at least 8 characters");
    }
    if !password.chars().any(|c| c.is_ascii_digit()) {
        return Err("must contain at least 1 digit");
    }
    if !password.chars().any(|c| c.is_ascii_lowercase()) {
        return Err("must contain at least 1 lowercase letter");
    }
    if !password.chars().any(|c| c.is_ascii_uppercase()) {
        return Err("must contain at least 1 uppercase letter");
    }
    Ok(())
}

pub fn is_leap_year(year: i32) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

/// その年月の日数（month は 1〜12）。
pub fn days_in_month(year: i32, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if is_leap_year(year) {
                29
            } else {
                28
            }
        }
        _ => 0,
    }
}

/// 実在する日付か（さらに今日以前か）を検証する。
pub fn validate_birthday(year: i32, month: u32, day: u32) -> Result<(), &'static str> {
    if !(1..=12).contains(&month) || day == 0 || day > days_in_month(year, month) {
        return Err("must be a valid date");
    }
    if (year, month, day) > today_utc() {
        return Err("must be in the past");
    }
    Ok(())
}

/// 現在の UTC 日付 (year, month, day)。
///
/// 依存追加を避けるため Unix 時刻から civil date を直接計算する
/// （Howard Hinnant の civil_from_days アルゴリズム）。
pub fn today_utc() -> (i32, u32, u32) {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    civil_from_days(secs.div_euclid(86_400))
}

/// 1970-01-01 からの日数 → (year, month, day)。
fn civil_from_days(days: i64) -> (i32, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097); // 0..=146096
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365; // 0..=399
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // 0..=365
    let mp = (5 * doy + 2) / 153; // 0..=11
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // 1..=31
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // 1..=12
    let year = if m <= 2 { y + 1 } else { y } as i32;
    (year, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn username_rules() {
        assert!(validate_username("frick").is_ok());
        assert!(validate_username("a_1").is_ok());
        assert!(validate_username("A2345678901234567890").is_ok()); // 20 chars

        assert!(validate_username("ab").is_err()); // too short
        assert!(validate_username("a23456789012345678901").is_err()); // 21 chars
        assert!(validate_username("has space").is_err());
        assert!(validate_username("héllo").is_err());
        assert!(validate_username("dash-ng").is_err());
    }

    #[test]
    fn email_rules() {
        assert!(validate_email("user@example.com").is_ok());
        assert!(validate_email("a@b").is_ok()); // auth 側の正規表現と同等の緩さ

        assert!(validate_email("no-at-sign").is_err());
        assert!(validate_email("@example.com").is_err());
        assert!(validate_email("user@").is_err());
        assert!(validate_email("two@@example.com").is_err());
        assert!(validate_email("sp ace@example.com").is_err());
    }

    #[test]
    fn password_rules() {
        assert!(validate_password("Secret123").is_ok());

        assert!(validate_password("Sh0rt").is_err()); // 8 文字未満
        assert!(validate_password("NoDigits").is_err());
        assert!(validate_password("nouppercase1").is_err());
        assert!(validate_password("NOLOWERCASE1").is_err());
    }

    #[test]
    fn month_lengths() {
        assert_eq!(days_in_month(2025, 1), 31);
        assert_eq!(days_in_month(2025, 4), 30);
        assert_eq!(days_in_month(2025, 2), 28);
        assert_eq!(days_in_month(2024, 2), 29); // leap
        assert_eq!(days_in_month(1900, 2), 28); // 100 で割り切れる
        assert_eq!(days_in_month(2000, 2), 29); // 400 で割り切れる
    }

    #[test]
    fn birthday_rules() {
        assert!(validate_birthday(2000, 1, 31).is_ok());
        assert!(validate_birthday(2024, 2, 29).is_ok());

        assert!(validate_birthday(2023, 2, 29).is_err()); // 実在しない
        assert!(validate_birthday(2000, 13, 1).is_err());
        assert!(validate_birthday(2000, 0, 1).is_err());
        assert!(validate_birthday(2000, 6, 0).is_err());
        assert!(validate_birthday(9999, 1, 1).is_err()); // 未来
    }

    #[test]
    fn civil_from_days_known_dates() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(19_723), (2024, 1, 1));
        assert_eq!(civil_from_days(-1), (1969, 12, 31));
    }

    #[test]
    fn today_is_sane() {
        let (y, m, d) = today_utc();
        assert!(y >= 2024);
        assert!((1..=12).contains(&m));
        assert!((1..=31).contains(&d));
    }
}
