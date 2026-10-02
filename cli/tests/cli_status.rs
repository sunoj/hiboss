// Purpose: Executable tests for `hiboss status`: exactly one GET, no PATCH, clean JSON stdout.
// Runs the real binary in a sandbox HOME against a synthetic 127.0.0.1 server; no real services.
// Dependencies: cli_ux_support (Sandbox, Loopback, signed_reply), serde_json.

#[allow(dead_code)] // Shared sandbox; this suite uses a subset of it.
mod cli_ux_support;
#[path = "cli_ux_support/loopback.rs"]
mod loopback;
#[path = "cli_ux_support/signing.rs"]
mod signing;

use cli_ux_support::{Outcome, Sandbox};
use loopback::Loopback;
use signing::signed_reply;
use serde_json::{Value, json};

const ONE_GET: [&str; 1] = ["GET /api/messages/msg_1"];

fn provenance(source: &str, status: &str) -> Value {
    json!({"source": source, "provenance": {"version": 1, "source": source,
        "signature": {"status": status}}})
}

fn reply(id: &str, body: Option<&str>, extra: Value) -> Value {
    let mut metadata = provenance("api", "not_configured");
    if let (Some(meta), Some(fields)) = (metadata.as_object_mut(), extra.as_object()) {
        meta.extend(fields.clone());
    }
    json!({"id": id, "direction": "boss_to_agent", "status": "sent", "body": body,
        "reply_to": "msg_1", "metadata": metadata})
}

fn auto_default_reply() -> Value {
    let mut metadata = provenance("system", "not_applicable");
    metadata["auto_default"] = json!(true);
    metadata["action"] = json!("deploy");
    json!({"id": "rep_auto", "direction": "boss_to_agent", "status": "sent",
        "body": "Approve", "reply_to": "msg_1", "metadata": metadata})
}

fn message(direction: &str, status: &str, metadata: Value, replies: Vec<Value>) -> Value {
    json!({"id": "msg_1", "direction": direction, "status": status, "body": "Deploy?",
        "metadata": metadata, "replies": replies})
}

/// Runs `hiboss status msg_1 [extra]` against a server answering every request the same way.
fn status(code: u16, body: &str, extra: &[&str]) -> (Outcome, Vec<String>) {
    let server = Loopback::start(code, body);
    let sandbox = Sandbox::new();
    let config = json!({"server": server.url(), "key": "synthetic-test-key"});
    sandbox.write_config(&config.to_string());
    let mut args = vec!["status", "msg_1"];
    args.extend_from_slice(extra);
    let out = sandbox.run_loopback(&args);
    (out, server.requests())
}

fn status_json(fixture: &Value) -> Value {
    let (out, requests) = status(200, &fixture.to_string(), &["--json"]);
    assert_eq!(out.code, 0, "stderr: {}", out.stderr);
    assert_eq!(requests, ONE_GET);
    assert!(out.stderr.is_empty(), "no progress text: {}", out.stderr);
    serde_json::from_str(&out.stdout).expect("stdout is exactly one JSON document")
}

#[test]
fn sent_and_delivered_are_read_with_one_get_and_no_patch() {
    for state in ["sent", "delivered"] {
        let fixture = message("agent_to_boss", state, json!({}), vec![]);
        let (out, requests) = status(200, &fixture.to_string(), &[]);
        assert_eq!(out.code, 0, "stderr: {}", out.stderr);
        assert_eq!(requests, ONE_GET, "state {state}");
        let expected = format!(
            "Message: msg_1\nDirection: agent_to_boss\nStatus: {state} (stored message state)\n\
             Replies: none recorded\n"
        );
        assert_eq!(out.stdout, expected);
        assert!(out.stderr.is_empty(), "no failure noise: {}", out.stderr);
    }
}

#[test]
fn replied_text_separates_reply_from_automatic_default() {
    let replies = vec![reply("rep_1", Some("Ship it"), json!({"action": "deploy"})), auto_default_reply()];
    let fixture = message("agent_to_boss", "replied", json!({}), replies);
    let (out, requests) = status(200, &fixture.to_string(), &[]);
    assert_eq!(out.code, 0, "stderr: {}", out.stderr);
    assert_eq!(requests, ONE_GET);
    assert!(out.stdout.contains("Status: replied (stored message state)\n"));
    assert!(out.stdout.contains(
        "Reply rep_1 [reply]: Ship it\n  Source: api/not_configured\n  Action: deploy\n"
    ));
    assert!(out.stdout.contains(
        "Reply rep_auto [auto_default]: Approve\n  Source: system/not_applicable\n  Automatic \
         timeout default recorded by the server; not a boss reply or execution authorization.\n"
    ));
    assert_eq!(out.stdout.matches("Action:").count(), 1, "{}", out.stdout);
}

#[test]
fn json_schema_exposes_actions_only_for_non_automatic_replies() {
    let replies = vec![reply("rep_1", Some("Ship it"), json!({"action": "deploy"})), auto_default_reply()];
    let doc = status_json(&message("agent_to_boss", "replied", json!({}), replies));
    assert_eq!(doc, json!({"message_id": "msg_1", "direction": "agent_to_boss",
        "status": "replied", "replies": [
            {"reply_id": "rep_1", "body": "Ship it", "outcome": "reply", "action": "deploy",
             "assurance": "api/not_configured"},
            {"reply_id": "rep_auto", "body": "Approve", "outcome": "auto_default", "action": null,
             "assurance": "system/not_applicable"}]}));
}

#[test]
fn agent_to_agent_is_read_without_side_effects() {
    let doc = status_json(&message("agent_to_agent", "delivered", json!({}), vec![]));
    assert_eq!(doc, json!({"message_id": "msg_1", "direction": "agent_to_agent",
        "status": "delivered", "replies": []}));
}

#[test]
fn expired_options_without_reply_claim_no_timeout_decision() {
    let meta = json!({"options_expired": true, "default_option": "Approve"});
    let fixture = message("agent_to_boss", "expired", meta, vec![]);
    let doc = status_json(&fixture);
    assert_eq!(doc["replies"], json!([]));
    assert_eq!(doc["status"], "expired");
    let (out, _) = status(200, &fixture.to_string(), &[]);
    assert!(out.stdout.contains("Options: expired\nReplies: none recorded\n"), "{}", out.stdout);
    assert!(!out.stdout.contains("auto_default") && !out.stdout.contains("Approve"));
}

#[test]
fn absent_body_and_non_boolean_auto_default_stay_factual() {
    let replies = vec![reply("rep_1", None, json!({"auto_default": "yes", "action": 5}))];
    let doc = status_json(&message("agent_to_boss", "replied", json!({}), replies));
    assert_eq!(doc["replies"], json!([{"reply_id": "rep_1", "body": null,
        "outcome": "reply", "action": null, "assurance": "api/not_configured"}]));
}

#[test]
fn malformed_metadata_fails_with_clean_stdout() {
    let mut bad = reply("rep_1", Some("Ship it"), json!({}));
    bad["metadata"] = json!("not an object");
    let fixture = message("agent_to_boss", "replied", json!({}), vec![bad]);
    for extra in [&["--json"][..], &[][..]] {
        let (out, requests) = status(200, &fixture.to_string(), extra);
        assert_eq!(out.code, 1, "stderr: {}", out.stderr);
        assert_eq!(requests, ONE_GET);
        assert!(out.stdout.is_empty(), "stdout: {}", out.stdout);
        assert!(out.stderr.starts_with("Error: "), "{}", out.stderr);
    }
}

#[test]
fn http_failure_reports_on_stderr_without_retry_or_patch() {
    for extra in [&["--json"][..], &[][..]] {
        let (out, requests) = status(500, r#"{"error":"synthetic failure"}"#, extra);
        assert_eq!(out.code, 2, "stderr: {}", out.stderr);
        assert_eq!(requests, ONE_GET);
        assert!(out.stdout.is_empty(), "stdout: {}", out.stdout);
        assert!(out.stderr.contains("request failed (500"), "{}", out.stderr);
    }
}

#[test]
fn assurance_separates_a_signed_native_reply_from_unsigned_ones() {
    let mut agent = reply("rep_agent", Some("FYI"), json!({}));
    agent["direction"] = json!("agent_to_agent");
    let replies = vec![signed_reply("rep_ios", "msg_1", "Ship it"),
        reply("rep_api", Some("Ship it"), json!({})), auto_default_reply(), agent];
    let fixture = message("agent_to_boss", "replied", json!({}), replies);
    let doc = status_json(&fixture);
    let labels: Vec<&Value> = doc["replies"].as_array().expect("replies").iter()
        .map(|reply| &reply["assurance"]).collect();
    assert_eq!(labels, ["ios/verified", "api/not_configured", "system/not_applicable", "agent"]);
    let (out, _) = status(200, &fixture.to_string(), &[]);
    assert!(out.stdout.contains("Reply rep_ios [reply]: Ship it\n  Source: ios/verified\n"));
    let api = "Reply rep_api [reply]: Ship it\n  Source: api/not_configured\n";
    assert!(out.stdout.contains(api), "{}", out.stdout);
}

#[test]
fn missing_metadata_or_provenance_is_a_failed_response_not_missing_config() {
    let mut no_metadata = reply("rep_1", Some("Ship it"), json!({}));
    no_metadata.as_object_mut().expect("reply").remove("metadata");
    let mut no_provenance = reply("rep_1", Some("Ship it"), json!({}));
    no_provenance["metadata"] = json!({"source": "api"});
    let cases = [(no_metadata, "missing metadata"), (no_provenance, "missing provenance")];
    for (bad, detail) in cases {
        let fixture = message("agent_to_boss", "replied", json!({}), vec![bad]);
        for extra in [&["--json"][..], &[][..]] {
            let (out, requests) = status(200, &fixture.to_string(), extra);
            assert_eq!(out.code, 1, "{detail}: {}", out.stderr);
            assert_eq!(requests, ONE_GET);
            assert!(out.stdout.is_empty(), "stdout: {}", out.stdout);
            let expected = format!("message rep_1 failed provenance verification: {detail}");
            assert_eq!(out.stderr, format!("Error: {expected}\n"));
        }
    }
}
