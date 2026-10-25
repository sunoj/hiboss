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
        "id": "reply-1", "direction": "boss_to_agent", "body": "Approve", "metadata": metadata,
    }))
    .expect("valid reply fixture")
}

/// A boss ask from agent-a carrying `replies`.
fn ask(replies: Vec<Message>) -> Message {
    let mut ask: Message = serde_json::from_value(json!({
        "id": "ask-1", "agent_id": "agent-a", "direction": "agent_to_boss",
    }))
    .expect("valid ask fixture");
    ask.replies = Some(replies);
    ask
}

#[test]
fn server_default_is_not_an_explicit_reply_or_action() {
    let result = AskResult::from_poll(
        "ask-1",
        Some(&ask(vec![reply(json!({
            "auto_default": true, "action": "deploy",
        }))])),
        &choices(),
    );
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
    for metadata in [
        json!({"action": "deploy"}),
        json!({"auto_default": false, "action": "deploy"}),
    ] {
        let result = AskResult::from_poll("ask-1", Some(&ask(vec![reply(metadata)])), &choices());
        assert_eq!(result.outcome, Outcome::Reply);
        assert_eq!(result.text(), "Approve");
        assert_eq!(result.action.as_deref(), Some("deploy"));
        assert_eq!(
            serde_json::to_value(result).expect("JSON")["outcome"],
            "reply"
        );
    }
}

#[test]
fn local_default_is_unconfirmed_and_has_no_action() {
    let empty = ask(Vec::new());
    for poll in [None, Some(&empty)] {
        let result = AskResult::from_poll("ask-1", poll, &choices());
        assert_eq!(result.outcome, Outcome::LocalDefault);
        assert!(result.reply_id.is_none());
        assert!(result.action.is_none());
        assert!(result.text().contains("not a confirmed server selection"));
        assert_eq!(
            serde_json::to_value(result).expect("JSON")["outcome"],
            "local_default"
        );
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
    assert_eq!(
        serde_json::to_value(result).expect("JSON")["outcome"],
        "timeout"
    );
}

#[test]
fn bodyless_reply_does_not_invent_a_default() {
    let mut reply = reply(json!({}));
    reply.body = None;
    let result = AskResult::from_poll("ask-1", Some(&ask(vec![reply])), &choices());
    assert_eq!(result.outcome, Outcome::Reply);
    assert!(result.body.is_none());
}

#[test]
fn reply_json_includes_the_answering_device() {
    let result = AskResult::from_poll(
        "ask-1",
        Some(&ask(vec![reply(json!({
            "answered_by": {"client_id": "mac", "kind": "macos", "label": "Mac mini"}
        }))])),
        &choices(),
    );
    assert_eq!(
        serde_json::to_value(result).expect("JSON")["device_label"],
        "Mac mini"
    );
}

#[test]
fn acknowledgement_links_to_the_boss_reply() {
    let hint = acknowledgement_hint("boss-reply-id");
    assert!(hint.contains("hiboss reply boss-reply-id \"<your response>\""));
    assert!(hint.contains("hiboss react boss-reply-id 👍"));
    assert!(!hint.contains("hiboss send"));
}

#[test]
fn non_boss_rows_are_not_a_reply() {
    let own: Message = serde_json::from_value(json!({
        "id": "own-1", "agent_id": "agent-a", "direction": "agent_to_boss", "body": "Approve",
    }))
    .expect("own follow-up");
    let forward: Message = serde_json::from_value(json!({
        "id": "fwd-1", "agent_id": "agent-a", "direction": "agent_to_boss", "type": "forwarded",
        "body": "[Forwarded from api] Deploy prod?",
    }))
    .expect("forward copy");
    // CONTROL: with no rows at all the configured default is a local fallback.
    assert_eq!(
        AskResult::from_poll("ask-1", None, &choices()).outcome,
        Outcome::LocalDefault
    );
    let result = AskResult::from_poll("ask-1", Some(&ask(vec![own, forward])), &choices());
    assert_eq!(result.outcome, Outcome::LocalDefault);
    assert!(result.reply_id.is_none());
}

#[test]
fn peer_answer_counts_but_the_askers_own_peer_row_does_not() {
    let row = |id: &str, agent: &str| -> Message {
        serde_json::from_value(json!({
            "id": id, "agent_id": agent, "direction": "agent_to_agent", "target_agent_id": "agent-a",
            "body": id,
        }))
        .expect("peer row")
    };
    let mut peer_ask = ask(vec![row("own-1", "agent-a"), row("peer-1", "agent-b")]);
    peer_ask.direction = Some("agent_to_agent".into());
    let result = AskResult::from_poll("ask-1", Some(&peer_ask), &choices());
    assert_eq!(
        (result.outcome, result.reply_id.as_deref()),
        (Outcome::Reply, Some("peer-1"))
    );
}

#[test]
fn same_agent_peer_answer_counts_only_from_another_session() {
    let row = |id: &str, session: serde_json::Value| -> Message {
        serde_json::from_value(json!({
            "id": id, "agent_id": "agent-a", "direction": "agent_to_agent", "target_agent_id": "agent-a",
            "session_id": session, "body": id,
        }))
        .expect("same-agent row")
    };
    let mut peer_ask = ask(vec![
        row("asker-1", json!("s1")),
        row("old-cli-1", json!(null)),
        row("peer-1", json!("s2")),
    ]);
    peer_ask.direction = Some("agent_to_agent".into());
    peer_ask.session_id = Some("s1".into());
    let result = AskResult::from_poll("ask-1", Some(&peer_ask), &choices());
    assert_eq!(
        (result.outcome, result.reply_id.as_deref()),
        (Outcome::Reply, Some("peer-1"))
    );
}
