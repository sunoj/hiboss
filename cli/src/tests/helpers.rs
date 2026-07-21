// Unit tests for shared helper functions and command-local utilities.
// Tests short_id and truncate from helpers module plus local AppleScript escaping.
// Dependencies: crate::helpers.

#[cfg(test)]
mod tests {
    use crate::helpers::{short_id, truncate, unescape_body};

    // Command-local functions tested here (not in shared module)
    fn escape_applescript(value: &str) -> String {
        value
            .replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
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
        assert_eq!(truncate("你好世界", 3), "...");
        assert_eq!(truncate("你好世界", 5), "你好世界");
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
        assert_eq!(escape_applescript("a\\b \"c\"\nd"), "a\\\\b \\\"c\\\"\\nd");
    }

    #[test]
    fn escape_empty_string() {
        assert_eq!(escape_applescript(""), "");
    }

    // --- unescape_body tests ---

    #[test]
    fn unescape_converts_newline() {
        assert_eq!(unescape_body("hello\\nworld"), "hello\nworld");
    }

    #[test]
    fn unescape_converts_tab() {
        assert_eq!(unescape_body("col1\\tcol2"), "col1\tcol2");
    }

    #[test]
    fn unescape_multiple_newlines() {
        assert_eq!(unescape_body("a\\n\\nb"), "a\n\nb");
    }

    #[test]
    fn unescape_no_escapes() {
        assert_eq!(unescape_body("plain text"), "plain text");
    }

    #[test]
    fn unescape_empty_string() {
        assert_eq!(unescape_body(""), "");
    }

    #[test]
    fn unescape_mixed() {
        assert_eq!(unescape_body("line1\\nline2\\tend"), "line1\nline2\tend");
    }
}
