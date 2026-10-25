// Purpose: Round-trip agent signing through the CLI verifier, as a peer agent would read it.
// Covers signed send/reply, tampering, recipient and time binding, and unsigned attribution.
// Dependencies: signing payload builders, message_security verifier, serde_json.

use super::{AgentSigner, sign_action, sign_send};
use crate::message_security::{assurance_label, verify_message};
use crate::types::Message;
use serde_json::{Map, Value, json};

fn request(fields: Value) -> Map<String, Value> {
    fields.as_object().expect("object").clone()
}

/// The row a server stores for `request`, with `overrides` applied to the top level.
fn stored(signer: &AgentSigner, request: &Map<String, Value>, direction: &str, overrides: Value) -> Message {
    let mut metadata = request.get("metadata").cloned().unwrap_or_else(|| json!({}));
    metadata["source"] = json!("agent");
    metadata["provenance"] = json!({
        "version": 1, "source": "agent", "actor": {"kind": "agent", "id": signer.agent_id},
        "authentication": {"kind": "agent_signature", "credential_id": signer.agent_key_id},
        "signature": {"scheme": "JWS-ES256", "key_id": signer.key_id, "public_key": signer.public_key,
            "signed_message": request["signed_message"]},
    });
    if let Some(options) = request.get("options") {
        metadata["options"] = options.clone();
    }
    let mut row = json!({"id": "msg-1", "agent_id": signer.agent_id, "direction": direction,
        "body": request["body"], "metadata": metadata, "created_at": now_rfc3339()});
    if let (Some(target), Some(fields)) = (row.as_object_mut(), overrides.as_object()) {
        target.extend(fields.clone());
    }
    serde_json::from_value(row).expect("message")
}

#[test]
fn signed_send_verifies_and_normalizes_like_the_server() {
    let signer = AgentSigner::ephemeral("agent-1", "cred-1");
    let mut body = request(json!({"body": "  Deploy done  ", "mode": "blocking", "priority": "normal",
        "options": [" Yes ", "No"], "metadata": {"content": "## Plan", "source": "ios"}}));
    sign_send(&signer, &mut body, json!({"kind": "boss"})).expect("sign");
    assert_eq!(body["body"], "Deploy done");
    assert_eq!(body["options"], json!(["Yes", "No"]));
    let message = stored(&signer, &body, "agent_to_boss", json!({}));
    verify_message(&message).expect("signed send verifies");
    assert_eq!(assurance_label(&message), "agent/verified");
}

#[test]
fn tampered_body_content_or_options_are_rejected() {
    let signer = AgentSigner::ephemeral("agent-1", "cred-1");
    let mut body = request(json!({"body": "Approve staging?", "mode": "blocking", "priority": "normal",
        "options": ["Yes", "No"], "metadata": {"content": "staging only"}}));
    sign_send(&signer, &mut body, json!({"kind": "boss"})).expect("sign");
    let swapped_body = stored(&signer, &body, "agent_to_boss", json!({"body": "Approve prod?"}));
    assert!(verify_message(&swapped_body).is_err());
    let mut swapped_content = stored(&signer, &body, "agent_to_boss", json!({}));
    swapped_content.metadata.as_mut().expect("metadata").insert("content".into(), json!("prod too"));
    assert!(verify_message(&swapped_content).is_err());
    let mut swapped_options = stored(&signer, &body, "agent_to_boss", json!({}));
    swapped_options.metadata.as_mut().expect("metadata").insert("options".into(), json!(["Yes", "Deploy prod"]));
    assert!(verify_message(&swapped_options).is_err());
    assert_eq!(assurance_label(&swapped_body), "invalid");
}

#[test]
fn recipient_sender_and_time_are_bound() {
    let signer = AgentSigner::ephemeral("agent-1", "cred-1");
    let mut peer = request(json!({"body": "Rebased", "mode": "async", "priority": "normal", "to": "otter-2"}));
    sign_send(&signer, &mut peer, json!({"kind": "agent", "agent_id": "agent-2", "session_id": "sess-2"})).expect("sign");
    let to_b = json!({"target_agent_id": "agent-2", "target_session_id": "sess-2"});
    verify_message(&stored(&signer, &peer, "agent_to_agent", to_b.clone())).expect("peer message verifies");
    let readdressed = json!({"target_agent_id": "agent-3", "target_session_id": "sess-3"});
    assert!(verify_message(&stored(&signer, &peer, "agent_to_agent", readdressed)).is_err());
    assert!(verify_message(&stored(&signer, &peer, "agent_to_boss", json!({}))).is_err());
    let mut forged_sender = to_b.clone();
    forged_sender["agent_id"] = json!("agent-9");
    assert!(verify_message(&stored(&signer, &peer, "agent_to_agent", forged_sender)).is_err());
    let mut redated = to_b;
    redated["created_at"] = json!("2001-01-01 00:00:00");
    assert!(verify_message(&stored(&signer, &peer, "agent_to_agent", redated)).is_err());
}

#[test]
fn a_row_cannot_gain_a_recipient_options_or_a_file_its_signature_lacks() {
    let signer = AgentSigner::ephemeral("agent-1", "cred-1");
    let mut body = request(json!({"body": "Status", "mode": "async", "priority": "normal"}));
    sign_send(&signer, &mut body, json!({"kind": "boss"})).expect("sign");
    let readdressed = stored(&signer, &body, "agent_to_boss", json!({"target_agent_id": "agent-3"}));
    assert!(verify_message(&readdressed).is_err(), "a boss-addressed row must not name a peer");
    for (key, value) in [("options", json!(["Approve deployment", "Reject"])), ("file_url", json!("https://x/evil.sh"))] {
        let mut row = stored(&signer, &body, "agent_to_boss", json!({}));
        row.metadata.as_mut().expect("metadata").insert(key.into(), value);
        assert!(verify_message(&row).is_err(), "{key} added after signing must fail");
    }
}

fn now_rfc3339() -> String {
    time::OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339).expect("format")
}

#[test]
fn a_signed_row_needs_a_valid_creation_time() {
    let signer = AgentSigner::ephemeral("agent-1", "cred-1");
    let mut body = request(json!({"body": "Status", "mode": "async", "priority": "normal"}));
    sign_send(&signer, &mut body, json!({"kind": "boss"})).expect("sign");
    let sqlite = time::OffsetDateTime::now_utc()
        .format(&time::format_description::parse("[year]-[month]-[day] [hour]:[minute]:[second]").expect("fmt"))
        .expect("format");
    verify_message(&stored(&signer, &body, "agent_to_boss", json!({"created_at": sqlite}))).expect("SQLite UTC time");
    for bad in [json!(null), json!(""), json!("not-a-date")] {
        let row = stored(&signer, &body, "agent_to_boss", json!({"created_at": bad}));
        assert!(verify_message(&row).is_err(), "created_at {bad} must fail");
    }
}

#[test]
fn signed_reply_is_bound_to_its_parent() {
    let signer = AgentSigner::ephemeral("agent-1", "cred-1");
    let mut reply = request(json!({"body": "Done"}));
    sign_action(&signer, &mut reply, json!({"kind": "reply", "message_id": "parent-1", "audience": {"kind": "boss"}})).expect("sign");
    verify_message(&stored(&signer, &reply, "agent_to_boss", json!({"reply_to": "parent-1"}))).expect("reply");
    assert!(verify_message(&stored(&signer, &reply, "agent_to_boss", json!({"reply_to": "parent-2"}))).is_err());
}

#[test]
fn unsigned_agent_rows_are_attributed_and_forged_sources_rejected() {
    let base = json!({"id": "msg-1", "agent_id": "agent-1", "direction": "agent_to_agent", "body": "hi"});
    let legacy: Message = serde_json::from_value(base.clone()).expect("legacy");
    assert_eq!(assurance_label(&legacy), "agent");
    let mut bearer = base.clone();
    bearer["metadata"] = json!({"source": "agent", "provenance": {"version": 1, "source": "agent",
        "signature": {"status": "not_configured"}}});
    let bearer: Message = serde_json::from_value(bearer).expect("bearer");
    assert_eq!(assurance_label(&bearer), "agent/not_configured");
    let mut forged = base;
    forged["metadata"] = json!({"source": "ios", "provenance": {"version": 1, "source": "ios",
        "signature": {"status": "not_configured"}}});
    let forged: Message = serde_json::from_value(forged).expect("forged");
    assert!(verify_message(&forged).is_err());
}

/// The MCP plugin imports this file's PKCS#8 with Web Crypto; mcp/agent-signer.test.ts builds
/// the same layout, so a change in ring's template must fail here first.
#[test]
fn key_files_use_the_pkcs8_layout_the_mcp_plugin_imports() {
    use ring::rand::SystemRandom;
    use ring::signature::{ECDSA_P256_SHA256_FIXED_SIGNING, EcdsaKeyPair};
    let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_FIXED_SIGNING, &SystemRandom::new()).expect("key");
    let bytes = pkcs8.as_ref();
    let hex: String = bytes[..36].iter().map(|byte| format!("{byte:02x}")).collect();
    assert_eq!(hex, "308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b0201010420");
    assert_eq!(bytes.len(), 138);
    assert_eq!(&bytes[68..73], &[0xa1, 0x44, 0x03, 0x42, 0x00]);
}
