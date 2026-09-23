// Regression coverage for server defaults, local fallback, and explicit replies.
use super::*;
use serde_json::json;
use std::collections::HashMap;

fn choices() -> ChoicePayload {
    ChoicePayload {
        options: Some(vec!["Approve".into(), "Reject".into()]),
        actions: HashMap::from([("Approve".into(), json!("deploy"))]),
        default_option: Some("Approve".into()),
    }
}

fn reply(metadata: serde_json::Value) -> Message {
    serde_json::from_value(json!({
        "id": "reply-1", "body": "Approve", "metadata": metadata,
    })).expect("valid reply fixture")
}

#[test]
fn server_default_is_not_an_explicit_reply_or_action() {
    let result = AskResult::from_poll("ask-1", Some(&[reply(json!({
        "auto_default": true, "action": "deploy",
    }))]), &choices());
    let json = serde_json::to_value(&result).expect("serializable result");
    assert_eq!(json["outcome"], "auto_default");
    assert_eq!(json["reply_id"], "reply-1");
    assert_eq!(json["message_id"], "ask-1");
    assert!(json["action"].is_null());
    assert!(result.text().starts_with("[auto_default] Approve"));
    assert!(result.text().contains("not a boss reply"));
}

#[test]
fn explicit_reply_matching_default_keeps_its_action() {
    for metadata in [json!({"action": "deploy"}), json!({"auto_default": false, "action": "deploy"})] {
        let result = AskResult::from_poll("ask-1", Some(&[reply(metadata)]), &choices());
        assert_eq!(result.outcome, Outcome::Reply);
        assert_eq!(result.text(), "Approve");
        assert_eq!(result.action.as_deref(), Some("deploy"));
        assert_eq!(serde_json::to_value(result).expect("JSON")["outcome"], "reply");
    }
}

#[test]
fn local_default_is_unconfirmed_and_has_no_action() {
    for replies in [None, Some(&[][..])] {
        let result = AskResult::from_poll("ask-1", replies, &choices());
        assert_eq!(result.outcome, Outcome::LocalDefault);
        assert!(result.reply_id.is_none());
        assert!(result.action.is_none());
        assert!(result.text().contains("not a confirmed server selection"));
        assert_eq!(serde_json::to_value(result).expect("JSON")["outcome"], "local_default");
    }
}

#[test]
fn timeout_without_default_preserves_recovery_id() {
    let mut choices = choices();
    choices.default_option = None;
    let result = AskResult::from_poll("ask-1", None, &choices);
    assert_eq!(result.outcome, Outcome::Timeout);
    assert_eq!(result.text(), "ask-1");
    assert!(result.body.is_none());
    assert_eq!(serde_json::to_value(result).expect("JSON")["outcome"], "timeout");
}

#[test]
fn bodyless_reply_does_not_invent_a_default() {
    let mut reply = reply(json!({}));
    reply.body = None;
    let result = AskResult::from_poll("ask-1", Some(&[reply]), &choices());
    assert_eq!(result.outcome, Outcome::Reply);
    assert!(result.body.is_none());
}
