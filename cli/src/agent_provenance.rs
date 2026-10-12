// Purpose: Verify agent-authored message provenance before a body reaches an AI agent.
// Exports: verify_agent_row (agent rows), verify_agent_signature (signed JWS checks).
// Dependencies: message_security helpers, ring ES256 verification, serde_json, time.

use crate::message_security::{
    MessageAssurance, MessageVerificationError, decode, decode_required, fail, object, required, string,
    verify_attribution,
};
use crate::types::Message;
use ring::digest::{SHA256, digest};
use ring::signature::{ECDSA_P256_SHA256_FIXED, UnparsedPublicKey};
use serde_json::{Map, Value};

const JWS_TYPE: &str = "hiboss-agent-message+jws";
const PURPOSE: &str = "hiboss.agent-message";
const MAX_SKEW_SECONDS: i64 = 300;
/// Client-owned metadata a reader sees and the signature must match exactly.
const SIGNED_METADATA: &[&str] = &["content", "summary", "default_option", "task_context"];

type Checked<T> = Result<T, MessageVerificationError>;

/// Rows without provenance predate attribution and stay `agent`; any provenance present must hold.
pub(crate) fn verify_agent_row(message: &Message) -> Checked<MessageAssurance> {
    let Some(metadata) = message.metadata.as_ref() else { return Ok(MessageAssurance::NotApplicable) };
    let Some(value) = metadata.get("provenance") else { return Ok(MessageAssurance::NotApplicable) };
    let provenance = value.as_object().ok_or_else(|| fail(message, "invalid provenance"))?;
    if provenance.get("version").and_then(Value::as_u64) != Some(1) {
        return Err(fail(message, "unsupported provenance version"));
    }
    let source = string(provenance, "source").ok_or_else(|| fail(message, "missing source"))?;
    if metadata.get("source").and_then(Value::as_str) != Some(source) {
        return Err(fail(message, "source attribution mismatch"));
    }
    if source != "agent" && source != "system" {
        return Err(fail(message, "agent message carries a non-agent source"));
    }
    let signature = object(provenance.get("signature"))
        .ok_or_else(|| fail(message, "missing signature state"))?;
    if signature.contains_key("scheme") {
        return verify_agent_signature(message, provenance, signature);
    }
    verify_attribution(message, signature, source)
}

pub(crate) fn verify_agent_signature(
    message: &Message,
    provenance: &Map<String, Value>,
    signature: &Map<String, Value>,
) -> Checked<MessageAssurance> {
    if string(signature, "scheme") != Some("JWS-ES256") {
        return Err(fail(message, "unsupported signature scheme"));
    }
    let key_id = required(message, signature, "key_id")?;
    let public_key = decode_required(message, signature, "public_key")?;
    if decode(key_id).map_err(|detail| fail(message, detail))? != digest(&SHA256, &public_key).as_ref() {
        return Err(fail(message, "signing key identifier mismatch"));
    }
    let compact = required(message, signature, "signed_message")?;
    let payload = verified_payload(message, compact, key_id, &public_key)?;
    let actor = object(provenance.get("actor")).and_then(|actor| string(actor, "id"));
    if actor.is_none() || payload.get("agent_id").and_then(Value::as_str) != actor {
        return Err(fail(message, "signed agent identity mismatch"));
    }
    check_content(message, &payload, actor.unwrap_or_default())?;
    Ok(MessageAssurance::Verified { source: "agent".to_owned(), key_id: key_id.to_owned() })
}

fn verified_payload(message: &Message, compact: &str, key_id: &str, public_key: &[u8]) -> Checked<Map<String, Value>> {
    let segments: Vec<&str> = compact.split('.').collect();
    if segments.len() != 3 || segments.iter().any(|segment| segment.is_empty()) {
        return Err(fail(message, "malformed compact JWS"));
    }
    let header = json_segment(message, segments[0])?;
    if string(&header, "alg") != Some("ES256") || string(&header, "typ") != Some(JWS_TYPE)
        || string(&header, "kid") != Some(key_id) {
        return Err(fail(message, "JWS header mismatch"));
    }
    let raw = decode(segments[2]).map_err(|detail| fail(message, detail))?;
    UnparsedPublicKey::new(&ECDSA_P256_SHA256_FIXED, public_key)
        .verify(format!("{}.{}", segments[0], segments[1]).as_bytes(), &raw)
        .map_err(|_| fail(message, "invalid ES256 signature"))?;
    let payload = json_segment(message, segments[1])?;
    if payload.get("version").and_then(Value::as_u64) != Some(1) || string(&payload, "purpose") != Some(PURPOSE)
        || string(&payload, "message_id").is_none() || payload.get("issued_at").and_then(Value::as_i64).is_none() {
        return Err(fail(message, "signed payload contract mismatch"));
    }
    Ok(payload)
}

fn check_content(message: &Message, payload: &Map<String, Value>, actor: &str) -> Checked<()> {
    if message.body.as_deref() != payload.get("body").and_then(Value::as_str) {
        return Err(fail(message, "signed body mismatch"));
    }
    let action = object(payload.get("action")).ok_or_else(|| fail(message, "missing signed action"))?;
    let target = string(action, "message_id");
    let consistent = match string(action, "kind") {
        Some("send") => message.reply_to.is_none() && audience_matches(message, action),
        Some("reply") => message.reply_to.as_deref() == target && audience_matches(message, action),
        _ => false,
    };
    if !consistent || message.agent_id.as_deref() != Some(actor) {
        return Err(fail(message, "signed action does not match the message"));
    }
    check_metadata(message, payload)?;
    check_issued_at(message, payload)
}

/// The signed recipient must be the row's: the boss, or the exact peer agent and session.
fn audience_matches(message: &Message, action: &Map<String, Value>) -> bool {
    let Some(audience) = object(action.get("audience")) else { return false };
    let direction = message.direction.as_deref();
    match string(audience, "kind") {
        Some("boss") => direction == Some("agent_to_boss") && untargeted(message),
        Some("agent") => direction == Some("agent_to_agent")
            && message.target_agent_id.as_deref() == string(audience, "agent_id")
            && message.target_session_id.as_deref() == audience.get("session_id").and_then(Value::as_str),
        _ => false,
    }
}

/// A row addressed to the boss names no peer; a recipient added later would expose it.
fn untargeted(message: &Message) -> bool {
    message.target_agent_id.is_none() && message.target_session_id.is_none()
}

fn check_metadata(message: &Message, payload: &Map<String, Value>) -> Checked<()> {
    let stored = message.metadata.as_ref();
    let signed = object(payload.get("metadata"));
    for key in SIGNED_METADATA {
        if signed.and_then(|fields| fields.get(*key)) != stored.and_then(|fields| fields.get(*key)) {
            return Err(fail(message, &format!("signed {key} mismatch")));
        }
    }
    // Absent and null are the same: a row cannot gain options or a file its signature lacks.
    for key in ["options", "file_url"] {
        let signed = payload.get(key).filter(|value| !value.is_null());
        if signed != stored.and_then(|fields| fields.get(key)).filter(|value| !value.is_null()) {
            return Err(fail(message, &format!("signed {key} mismatch")));
        }
    }
    Ok(())
}

/// A stored row cannot be re-dated: its creation time must sit within the signing window.
fn check_issued_at(message: &Message, payload: &Map<String, Value>) -> Checked<()> {
    let issued = payload.get("issued_at").and_then(Value::as_i64)
        .ok_or_else(|| fail(message, "signed payload has no issued_at"))?;
    let created = message.created_at.as_deref().and_then(parse_timestamp)
        .ok_or_else(|| fail(message, "signed message has no valid created_at"))?;
    if (created - issued).abs() > MAX_SKEW_SECONDS {
        return Err(fail(message, "signed time does not match the stored message"));
    }
    Ok(())
}

fn parse_timestamp(value: &str) -> Option<i64> {
    use time::{OffsetDateTime, PrimitiveDateTime, format_description, format_description::well_known::Rfc3339};
    if let Ok(parsed) = OffsetDateTime::parse(value, &Rfc3339) {
        return Some(parsed.unix_timestamp());
    }
    let sqlite = format_description::parse("[year]-[month]-[day] [hour]:[minute]:[second]").ok()?;
    PrimitiveDateTime::parse(value, &sqlite).ok().map(|parsed| parsed.assume_utc().unix_timestamp())
}

fn json_segment(message: &Message, encoded: &str) -> Checked<Map<String, Value>> {
    let bytes = decode(encoded).map_err(|detail| fail(message, detail))?;
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(Value::Object(fields)) => Ok(fields),
        _ => Err(fail(message, "invalid JWS segment")),
    }
}
