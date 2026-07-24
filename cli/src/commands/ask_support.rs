// Purpose: Ask-command helpers shared between arg parsing and run loop.
// Exports: ChoicePayload default-option validation, default-reply resolution,
// metadata construction, unread-message pre-warning.
// Dependencies: serde_json::Value, crate::client, crate::session, crate::types,
// super::ask.

use crate::client::HiBossClient;
use crate::types::Message;
use serde_json::Value;
use std::collections::HashMap;

use super::ask::{AskInputError, ChoicePayload};

/// Pure resolution of the default reply when the boss did not answer in time.
/// Returns Some(label + optional action command) only when a default was
/// configured and no real reply is present.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct DefaultReply {
    pub(crate) label: String,
    pub(crate) action: Option<Value>,
}

pub(crate) fn resolve_default_reply(
    choices: &ChoicePayload,
    replies: Option<&[Message]>,
) -> Option<DefaultReply> {
    if let Some(replies) = replies {
        if replies.first().is_some() {
            return None;
        }
    }
    let label = choices.default_option.as_ref()?;
    let action = choices.actions.get(label).cloned();
    Some(DefaultReply {
        label: label.clone(),
        action,
    })
}

pub(crate) fn validate_default_option(
    raw: &Option<String>,
    options: Option<&[String]>,
) -> Result<Option<String>, AskInputError> {
    let Some(label) = raw else {
        return Ok(None);
    };
    let label = label.trim();
    if label.is_empty() {
        return Err(AskInputError::EmptyChoice);
    }
    let labels = options.unwrap_or(&[]);
    if !labels.iter().any(|choice| choice == label) {
        return Err(AskInputError::DefaultNotInChoices(label.to_owned()));
    }
    Ok(Some(label.to_owned()))
}

pub(crate) fn action_metadata(
    actions: &HashMap<String, Value>,
    default_option: Option<&str>,
    summary: Option<&str>,
    content: Option<&str>,
) -> Result<Option<HashMap<String, Value>>, serde_json::Error> {
    let mut metadata: HashMap<String, Value> = HashMap::new();
    if !actions.is_empty() {
        metadata.insert("actions".to_owned(), serde_json::to_value(actions)?);
    }
    if let Some(label) = default_option {
        metadata.insert("default_option".to_owned(), Value::String(label.to_owned()));
    }
    if let Some(s) = summary {
        metadata.insert("summary".to_owned(), Value::String(s.to_owned()));
    }
    if let Some(s) = content {
        if !s.is_empty() {
            metadata.insert("content".to_owned(), Value::String(s.to_owned()));
        }
    }
    if metadata.is_empty() {
        return Ok(None);
    }
    Ok(Some(metadata))
}

/// Check for unread boss messages before sending. Warns via stdout so the AI sees it.
pub(crate) async fn warn_unread_messages(client: &HiBossClient) {
    let sid = crate::session::read_session_id();
    let boss_count = client.inbox_count(None, sid.as_deref()).await.unwrap_or(0);
    let a2a_count = client.inbox_count_a2a(sid.as_deref()).await.unwrap_or(0);
    if boss_count > 0 || a2a_count > 0 {
        if boss_count > 0 {
            println!(
                "UNREAD WARNING: You have {} unread boss message(s). Read them FIRST: hiboss inbox",
                boss_count
            );
        }
        if a2a_count > 0 {
            println!(
                "UNREAD WARNING: You have {} unread peer message(s). Read them FIRST: hiboss inbox --direction agent_to_agent",
                a2a_count
            );
        }
        println!(
            "Reply to unread messages with: hiboss reply <id> \"response\" BEFORE sending new messages."
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::ask::ChoicePayload;
    use std::collections::HashMap;

    fn payload(default: Option<&str>, labels: &[&str]) -> ChoicePayload {
        ChoicePayload {
            options: Some(labels.iter().map(|s| (*s).to_owned()).collect()),
            actions: HashMap::new(),
            default_option: default.map(|s| s.to_owned()),
        }
    }

    #[test]
    fn no_reply_with_default_returns_the_default() {
        let choices = payload(Some("A"), &["A", "B"]);
        let resolved = resolve_default_reply(&choices, None);
        assert_eq!(
            resolved,
            Some(DefaultReply {
                label: "A".to_owned(),
                action: None,
            })
        );
    }

    #[test]
    fn real_reply_suppresses_the_default() {
        let choices = payload(Some("A"), &["A", "B"]);
        let reply = crate::types::Message {
            id: "r1".to_owned(),
            agent_id: None,
            agent_name: None,
            direction: None,
            mode: None,
            channel: None,
            body: Some("boss".to_owned()),
            status: None,
            reply_to: None,
            priority: None,
            message_type: None,
            metadata: None,
            created_at: None,
            updated_at: None,
            session_id: None,
            session_label: None,
            session_branch: None,
            session_status: None,
            replies: None,
        };
        let resolved = resolve_default_reply(&choices, Some(&[reply]));
        assert!(resolved.is_none());
    }

    #[test]
    fn validate_accepts_a_known_label() {
        let raw = Some("B".to_owned());
        let labels = vec!["A".to_owned(), "B".to_owned()];
        let result = validate_default_option(&raw, Some(&labels)).expect("valid default");
        assert_eq!(result, Some("B".to_owned()));
    }

    #[test]
    fn validate_rejects_an_unknown_label() {
        let raw = Some("Z".to_owned());
        let labels = vec!["A".to_owned(), "B".to_owned()];
        let result = validate_default_option(&raw, Some(&labels));
        assert!(matches!(
            result,
            Err(AskInputError::DefaultNotInChoices(label)) if label == "Z"
        ));
    }

    #[test]
    fn validate_rejects_default_without_options() {
        let raw = Some("A".to_owned());
        let result = validate_default_option(&raw, None);
        assert!(matches!(result, Err(AskInputError::DefaultNotInChoices(_))));
    }

    #[test]
    fn metadata_includes_default_option_in_plain_option_mode() {
        let actions = HashMap::new();
        let result = action_metadata(&actions, Some("A"), None, None)
            .expect("metadata builds")
            .expect("metadata present");
        assert_eq!(
            result.get("default_option"),
            Some(&Value::String("A".to_owned()))
        );
    }

    #[test]
    fn metadata_includes_actions_and_default_together() {
        let mut actions = HashMap::new();
        actions.insert("A".to_owned(), Value::String("deploy".to_owned()));
        let result = action_metadata(&actions, Some("A"), None, None)
            .expect("metadata builds")
            .expect("metadata present");
        assert_eq!(
            result.get("default_option"),
            Some(&Value::String("A".to_owned()))
        );
        assert!(result.get("actions").is_some());
    }

    #[test]
    fn metadata_includes_content() {
        let actions = HashMap::new();
        let result = action_metadata(&actions, None, None, Some("retry window"))
            .expect("metadata builds")
            .expect("metadata present");
        assert_eq!(
            result.get("content"),
            Some(&Value::String("retry window".to_owned()))
        );
    }

    #[test]
    fn metadata_omits_empty_content() {
        let actions = HashMap::new();
        let result = action_metadata(&actions, None, None, Some(""))
            .expect("metadata builds");
        assert!(result.is_none());
    }
}
