// Unit coverage for status reply classification and the human-readable status text.
// Only explicit metadata.auto_default == true marks an automatic default; it never has an action.
use super::*;
use serde_json::json;

fn message(value: Value) -> Message {
    serde_json::from_value(value).expect("valid message fixture")
}

#[test]
fn explicit_auto_default_drops_the_stored_action() {
    let reply = ReplyReport::from_reply(&message(json!({
        "id": "r1", "body": "Approve", "metadata": {"auto_default": true, "action": "deploy"},
    })));
    assert_eq!(reply.outcome, ReplyOutcome::AutoDefault);
    assert_eq!(reply.action, None);
    assert!(reply.text().contains("not a boss reply or execution authorization"));
}

#[test]
fn non_boolean_auto_default_is_not_a_discriminator() {
    let reply = ReplyReport::from_reply(&message(json!({
        "id": "r1", "body": "Approve", "metadata": {"auto_default": "true", "action": "deploy"},
    })));
    assert_eq!(reply.outcome, ReplyOutcome::Reply);
    assert_eq!(reply.action.as_deref(), Some("deploy"));
    assert_eq!(reply.text(), "Reply r1 [reply]: Approve\n  Source: agent\n  Action: deploy\n");
}

#[test]
fn boss_replies_carry_the_verifier_assurance_label() {
    let attributed = |source: &str, status: &str, extra: Value| {
        let mut meta = json!({"source": source,
            "provenance": {"version": 1, "source": source, "signature": {"status": status}}});
        let extra = extra.as_object().cloned().unwrap_or_default();
        meta.as_object_mut().expect("object").extend(extra);
        let mut reply = json!({"id": "r1", "direction": "boss_to_agent", "body": "Approve"});
        reply["metadata"] = meta;
        message(reply)
    };
    let api = ReplyReport::from_reply(&attributed("api", "not_configured", json!({})));
    assert_eq!(api.assurance, "api/not_configured");
    assert_eq!(api.text(), "Reply r1 [reply]: Approve\n  Source: api/not_configured\n");
    let auto_meta = json!({"auto_default": true});
    let auto = ReplyReport::from_reply(&attributed("system", "not_applicable", auto_meta));
    assert_eq!(auto.assurance, "system/not_applicable");
    assert!(auto.text().contains("\n  Source: system/not_applicable\n  Automatic timeout"));
}

#[test]
fn reply_without_body_or_string_action_reports_nulls() {
    let reply = ReplyReport::from_reply(&message(json!({"id": "r1", "metadata": {"action": 7}})));
    assert_eq!((reply.body, reply.action), (None, None));
}

#[test]
fn expired_options_without_reply_claim_no_decision() {
    let report = StatusReport::from_message(&message(json!({
        "id": "m1", "direction": "agent_to_boss", "status": "expired",
        "metadata": {"options_expired": true, "default_option": "Approve"}, "replies": [],
    })));
    let text = report.text();
    assert!(text.starts_with("Message: m1\nDirection: agent_to_boss\nStatus: expired"));
    assert!(text.contains("Options: expired\nReplies: none recorded\n"));
    assert!(!text.contains("auto_default") && !text.contains("Approve"));
}

#[test]
fn missing_fields_render_as_unknown_and_serialize_as_null() {
    let report = StatusReport::from_message(&message(json!({"id": "m1"})));
    assert!(report.text().contains("Direction: unknown\nStatus: unknown"));
    let value = serde_json::to_value(&report).expect("serializable report");
    assert_eq!(value, json!({"message_id": "m1", "direction": null, "status": null, "replies": []}));
}
