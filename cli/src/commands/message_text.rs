// Validates short message titles and loads complete Markdown details without truncation.
// Exports title and content helpers for send, ask, and edit commands.
// Dependencies: filesystem UTF-8 reads and existing body escape handling.

use std::{error::Error, path::Path};

pub(super) fn title(value: &str, is_peer: bool) -> Result<String, Box<dyn Error>> {
    let text = crate::helpers::unescape_body(value).trim().to_owned();
    if text.is_empty() {
        return Err("Message title is required".into());
    }
    if !is_peer && text.chars().count() > 144 {
        return Err("Message title exceeds 144 characters; use --content or --content-file for Markdown details".into());
    }
    Ok(text)
}

pub(super) fn content(
    inline: Option<&str>,
    file: Option<&Path>,
) -> Result<Option<String>, Box<dyn Error>> {
    match (inline, file) {
        (Some(_), Some(_)) => Err("Use either --content or --content-file".into()),
        (_, Some(path)) => Ok(Some(std::fs::read_to_string(path)?)),
        (Some(text), None) => Ok(Some(crate::helpers::unescape_body(text))),
        (None, None) => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn title_counts_unicode_scalars_and_does_not_limit_peer_text() {
        assert!(title(&"🏠".repeat(144), false).is_ok());
        assert!(title(&"字".repeat(145), false).is_err());
        assert!(title(&"x".repeat(200), true).is_ok());
        assert!(title(" ", false).is_err());
    }

    #[test]
    fn content_preserves_lines_and_rejects_two_sources() {
        assert_eq!(
            content(Some("**Ready**\\n\\n- Done"), None).expect("content"),
            Some("**Ready**\n\n- Done".into())
        );
        assert!(content(Some("inline"), Some(Path::new("unused"))).is_err());
    }
}
