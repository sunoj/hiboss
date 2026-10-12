// Purpose: Normalize message request bodies and attach the agent's signed_message JWS.
// Exports: sign_send, sign_action — both mutate a JSON request body in place.
// Dependencies: ring random bytes, serde_json, and compact JWS encoding.

use super::{jws::compact, store::AgentSigner};
use ring::rand::{SecureRandom, SystemRandom};
use serde_json::{Map, Value, json};
use std::{error::Error, time::SystemTime};

const MESSAGE_TYPE: &str = "hiboss-agent-message+jws";
/// Keys the server owns and strips from client metadata; a signature never covers them.
const SERVER_OWNED: &[&str] = &[
    "provenance", "source", "boss_id", "boss_name", "auto_default",
    "ask_deadline", "options", "file_url", "options_resolved", "options_expired", "selected_option",
    "reactions", "telegram_message_id", "telegram_chat_id", "discord_message_id",
    "delivery_results", "delivery_error",
];

/// Signs a POST /api/messages body after normalizing it exactly as the server will.
/// `audience` is `{kind: "boss"}` or the resolved `{kind: "agent", agent_id, session_id}`.
pub fn sign_send(signer: &AgentSigner, request: &mut Map<String, Value>, audience: Value) -> Result<(), Box<dyn Error>> {
    let body = trimmed(request.get("body")).unwrap_or_default();
    request.insert("body".into(), Value::String(body.clone()));
    let options = request.get("options").and_then(Value::as_array).map(|items| {
        items.iter().map(|item| Value::String(item.as_str().unwrap_or_default().trim().to_owned())).collect::<Vec<_>>()
    });
    if let Some(items) = &options {
        request.insert("options".into(), Value::Array(items.clone()));
    }
    let mode = match request.get("mode").and_then(Value::as_str) {
        Some("blocking") => "blocking",
        _ => "async",
    };
    let content = json!({
        "session_id": trimmed(request.get("session_id")).filter(|value| !value.is_empty()),
        "action": { "kind": "send", "audience": audience },
        "body": body,
        "mode": mode,
        "timeout": request.get("timeout").filter(|value| value.is_number()).cloned(),
        "file_url": trimmed(request.get("file_url")).filter(|value| !value.is_empty()),
        "options": options,
        "metadata": client_metadata(request.get("metadata")),
    });
    attach(signer, request, content)
}

/// Signs a reply, forward or boss reply: only the action and the body are signed.
pub fn sign_action(
    signer: &AgentSigner,
    request: &mut Map<String, Value>,
    action: Value,
) -> Result<(), Box<dyn Error>> {
    let body = trimmed(request.get("body")).unwrap_or_default();
    request.insert("body".into(), Value::String(body.clone()));
    let content = json!({
        "session_id": null, "action": action, "body": body, "mode": null,
        "timeout": null, "file_url": null, "options": null, "metadata": null,
    });
    attach(signer, request, content)
}

fn attach(signer: &AgentSigner, request: &mut Map<String, Value>, content: Value) -> Result<(), Box<dyn Error>> {
    let mut payload = json!({
        "version": 1,
        "purpose": "hiboss.agent-message",
        "message_id": uuid_v4()?,
        "issued_at": now()?,
        "agent_id": signer.agent_id,
    });
    if let (Some(target), Value::Object(fields)) = (payload.as_object_mut(), content) {
        target.extend(fields);
    }
    let token = compact(signer, MESSAGE_TYPE, &payload)?;
    request.remove("idempotency_key");
    request.insert("signed_message".into(), Value::String(token));
    Ok(())
}

fn client_metadata(value: Option<&Value>) -> Value {
    let Some(Value::Object(fields)) = value else { return Value::Null };
    let kept: Map<String, Value> = fields
        .iter()
        .filter(|(key, _)| !SERVER_OWNED.contains(&key.as_str()))
        .map(|(key, value)| (key.clone(), value.clone()))
        .collect();
    if kept.is_empty() { Value::Null } else { Value::Object(kept) }
}

fn trimmed(value: Option<&Value>) -> Option<String> {
    value.and_then(Value::as_str).map(|text| text.trim().to_owned())
}

pub(super) fn now() -> Result<i64, Box<dyn Error>> {
    Ok(SystemTime::now().duration_since(SystemTime::UNIX_EPOCH)?.as_secs() as i64)
}

fn uuid_v4() -> Result<String, Box<dyn Error>> {
    let mut bytes = [0_u8; 16];
    SystemRandom::new().fill(&mut bytes).map_err(|_| "random generator unavailable")?;
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|byte| format!("{byte:02x}")).collect();
    Ok(format!("{}-{}-{}-{}-{}", &hex[..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..]))
}
