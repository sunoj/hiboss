// Purpose: Parse share-link lifetimes (`<n>h`, `<n>d` or plain seconds) within the server's bounds.
// Exports: parse, MIN_SECONDS, MAX_SECONDS; pure, used as a clap value parser.
pub(crate) const MIN_SECONDS: u64 = 3600;
pub(crate) const MAX_SECONDS: u64 = 30 * 86400;

pub(crate) fn parse(value: &str) -> Result<u64, String> {
    let (digits, unit) = if let Some(hours) = value.strip_suffix('h') {
        (hours, 3600)
    } else if let Some(days) = value.strip_suffix('d') {
        (days, 86400)
    } else {
        (value, 1)
    };
    let seconds = digits
        .parse::<u64>()
        .ok()
        .filter(|_| !digits.is_empty() && digits.bytes().all(|byte| byte.is_ascii_digit()))
        .and_then(|count| count.checked_mul(unit))
        .ok_or_else(|| format!("expected <n>h, <n>d or seconds (e.g. 12h, 7d), got '{value}'"))?;
    if !(MIN_SECONDS..=MAX_SECONDS).contains(&seconds) {
        return Err(format!(
            "share lifetime must be between 1h and 30d ({MIN_SECONDS}..{MAX_SECONDS} seconds), got {seconds}s"
        ));
    }
    Ok(seconds)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_hours_days_and_seconds_within_bounds() {
        assert_eq!(parse("1h"), Ok(3600));
        assert_eq!(parse("12h"), Ok(43200));
        assert_eq!(parse("7d"), Ok(604800));
        assert_eq!(parse("30d"), Ok(MAX_SECONDS));
        assert_eq!(parse("7200"), Ok(7200));
    }

    #[test]
    fn rejects_out_of_range_and_malformed_values() {
        for value in ["59m", "3599", "0h", "31d", "721h", "2592001"] {
            assert!(parse(value).is_err(), "{value} accepted");
        }
        assert!(parse("31d").unwrap_err().contains("between 1h and 30d"));
        for value in [
            "",
            "h",
            "d",
            "1.5h",
            "-1d",
            "+2h",
            "7 d",
            "1w",
            "99999999999999999999d",
        ] {
            assert!(
                parse(value).unwrap_err().contains("expected <n>h"),
                "{value}"
            );
        }
    }
}
