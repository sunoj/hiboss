// Unit tests for pure helper functions used across CLI commands.
// Tests short_id, truncate, escape_applescript, and options parsing logic.
// Dependencies: none (self-contained copies of the algorithms).

#[cfg(test)]
mod tests {
    // Copied from inbox.rs:53
    fn short_id(value: &str) -> String {
        value.chars().take(8).collect()
    }

    // Copied from inbox.rs:67
    fn truncate(input: &str, limit: usize) -> String {
        if input.chars().count() <= limit {
            input.to_string()
        } else {
            let truncated: String = input.chars().take(limit - 3).collect();
            format!("{}...", truncated)
        }
    }

    // Copied from watch.rs:88
    fn escape_applescript(value: &str) -> String {
        value
            .replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
    }

    // Copied from ask.rs:23-25
    fn parse_options(input: Option<&str>) -> Option<Vec<String>> {
        input
            .map(|o| {
                o.split(',')
                    .map(|s| s.trim().to_owned())
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>()
            })
            .filter(|v| !v.is_empty())
    }

    // --- short_id tests ---

    #[test]
    fn short_id_normal_hex() {
        assert_eq!(short_id("abcdef1234567890abcdef1234567890"), "abcdef12");
    }

    #[test]
    fn short_id_exactly_8_chars() {
        assert_eq!(short_id("12345678"), "12345678");
    }

    #[test]
    fn short_id_less_than_8() {
        assert_eq!(short_id("abc"), "abc");
    }

    #[test]
    fn short_id_empty() {
        assert_eq!(short_id(""), "");
    }

    #[test]
    fn short_id_unicode() {
        assert_eq!(short_id("你好世界测试数据额外"), "你好世界测试数据");
    }

    // --- truncate tests ---

    #[test]
    fn truncate_shorter_than_limit() {
        assert_eq!(truncate("hello", 10), "hello");
    }

    #[test]
    fn truncate_exactly_at_limit() {
        assert_eq!(truncate("hello", 5), "hello");
    }

    #[test]
    fn truncate_longer_than_limit() {
        assert_eq!(truncate("hello world!", 8), "hello...");
    }

    #[test]
    fn truncate_empty_string() {
        assert_eq!(truncate("", 10), "");
    }

    #[test]
    fn truncate_limit_of_3() {
        assert_eq!(truncate("abcdef", 3), "...");
    }

    #[test]
    fn truncate_unicode_multibyte() {
        // 4 unicode chars, limit 3 → take 0 chars + "..."
        assert_eq!(truncate("你好世界", 3), "...");
        // 4 chars, limit 5 → fits (4 <= 5), no truncation
        assert_eq!(truncate("你好世界", 5), "你好世界");
        // 5 chars, limit 4 → take 1 char + "..."
        assert_eq!(truncate("你好世界额", 4), "你...");
    }

    // --- escape_applescript tests ---

    #[test]
    fn escape_no_special_chars() {
        assert_eq!(escape_applescript("hello"), "hello");
    }

    #[test]
    fn escape_backslash() {
        assert_eq!(escape_applescript("a\\b"), "a\\\\b");
    }

    #[test]
    fn escape_double_quote() {
        assert_eq!(escape_applescript("say \"hi\""), "say \\\"hi\\\"");
    }

    #[test]
    fn escape_newline() {
        assert_eq!(escape_applescript("line1\nline2"), "line1\\nline2");
    }

    #[test]
    fn escape_all_combined() {
        assert_eq!(
            escape_applescript("a\\b \"c\"\nd"),
            "a\\\\b \\\"c\\\"\\nd"
        );
    }

    #[test]
    fn escape_empty_string() {
        assert_eq!(escape_applescript(""), "");
    }

    // --- parse_options tests ---

    #[test]
    fn options_comma_separated() {
        assert_eq!(
            parse_options(Some("A,B,C")),
            Some(vec!["A".to_string(), "B".to_string(), "C".to_string()])
        );
    }

    #[test]
    fn options_with_whitespace() {
        assert_eq!(
            parse_options(Some(" A , B ")),
            Some(vec!["A".to_string(), "B".to_string()])
        );
    }

    #[test]
    fn options_empty_segments_filtered() {
        assert_eq!(parse_options(Some(",,")), None);
    }

    #[test]
    fn options_empty_string() {
        assert_eq!(parse_options(Some("")), None);
    }

    #[test]
    fn options_single_value() {
        assert_eq!(
            parse_options(Some("single")),
            Some(vec!["single".to_string()])
        );
    }

    #[test]
    fn options_none_input() {
        assert_eq!(parse_options(None), None);
    }
}
