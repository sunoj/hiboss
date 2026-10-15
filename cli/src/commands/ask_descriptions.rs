// Parses plain-text option descriptions before ask uploads any attachments.
// Exports resolve_option_descriptions; depends on ChoicePayload and serde_json.

use super::ask::ChoicePayload;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::io::{Error, ErrorKind};

pub(crate) fn resolve_option_descriptions(
    raw: &[String],
    choices: &ChoicePayload,
) -> Result<Option<Vec<Value>>, Error> {
    let labels = choices.options.as_deref().unwrap_or(&[]);
    let mut seen = HashSet::new();
    let mut descriptions = Vec::new();
    for value in raw {
        let (label, text) = value.split_once('=').ok_or_else(|| {
            Error::new(
                ErrorKind::InvalidInput,
                "option descriptions require LABEL=TEXT",
            )
        })?;
        let (label, text) = (label.trim(), text.trim());
        let error = if label.is_empty() || !labels.iter().any(|choice| choice == label) {
            Some("option description label must match an --option/--action label")
        } else if !seen.insert(label.to_owned()) {
            Some("option description labels must be unique")
        } else if text.is_empty() || text.chars().count() > 200 {
            Some("option description text must contain 1 to 200 characters")
        } else {
            None
        };
        if let Some(message) = error {
            return Err(Error::new(ErrorKind::InvalidInput, message));
        }
        descriptions.push(json!({ "label": label, "text": text }));
    }
    Ok((!descriptions.is_empty()).then_some(descriptions))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn resolve(raw: &[&str], options: Option<Vec<String>>) -> Result<Option<Vec<Value>>, Error> {
        resolve_option_descriptions(
            &raw.iter()
                .map(|value| (*value).to_owned())
                .collect::<Vec<_>>(),
            &ChoicePayload {
                options,
                actions: HashMap::new(),
                default_option: None,
            },
        )
    }

    #[test]
    fn trims_and_preserves_equals_and_plain_text() {
        let result = resolve(&[" A = **x=y** "], Some(vec!["A".into(), "B".into()]));
        assert_eq!(
            result.expect("valid"),
            Some(vec![json!({"label":"A", "text":"**x=y**"})])
        );
        assert!(resolve(&[], None).expect("absent").is_none());
    }

    #[test]
    fn rejects_invalid_descriptions() {
        for raw in [
            vec!["A"],
            vec!["=text"],
            vec!["A= "],
            vec!["B=text"],
            vec!["A=x", " A =y"],
        ] {
            assert!(resolve(&raw, Some(vec!["A".into()])).is_err());
        }
        assert!(resolve(&["A=text"], None).is_err());
        let too_long = format!("A={}", "x".repeat(201));
        assert!(resolve(&[&too_long], Some(vec!["A".into()])).is_err());
        let boundary = format!("A={}", "😀".repeat(200));
        assert!(resolve(&[&boundary], Some(vec!["A".into()])).is_ok());
    }
}
