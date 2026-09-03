// Purpose: Verify boss-message provenance before message bodies reach an AI agent.
// Exports signature enforcement, assurance labels, and recursive message checks.
// Dependencies: API Message types, serde JSON, and ring ES256 verification.

use crate::types::Message;
use ring::digest::{digest, SHA256};
use ring::signature::{UnparsedPublicKey, ECDSA_P256_SHA256_FIXED};
use serde::Deserialize;
use serde_json::{Map, Value};
use std::error::Error;
use std::fmt::{Display, Formatter};

const SIGNATURE_SCHEME: &str = "JWS-ES256";
const JWS_TYPE: &str = "hiboss-message+jws";
const MESSAGE_PURPOSE: &str = "hiboss.boss-message";

#[derive(Debug, PartialEq, Eq)]
pub enum MessageAssurance {
    Verified { source: String, key_id: String },
    Attributed { source: String, status: String },
    NotApplicable,
}

#[derive(Debug)]
pub struct MessageVerificationError {
    message_id: String,
    detail: String,
}

impl Display for MessageVerificationError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "message {} failed provenance verification: {}", self.message_id, self.detail)
    }
}

impl Error for MessageVerificationError {}

#[derive(Deserialize)]
struct JwsHeader {
    alg: String,
    kid: String,
    typ: String,
}

#[derive(Deserialize)]
struct SignedAction {
    kind: String,
    message_id: String,
}

#[derive(Deserialize)]
struct SignedPayload {
    version: u8,
    purpose: String,
    message_id: String,
    issued_at: i64,
    boss_id: String,
    action: SignedAction,
    body: String,
}

pub fn verify_message(message: &Message) -> Result<MessageAssurance, MessageVerificationError> {
    let assurance = verify_single(message)?;
    for reply in message.replies.as_deref().unwrap_or_default() {
        verify_message(reply)?;
    }
    Ok(assurance)
}

pub fn verify_messages(messages: &[Message]) -> Result<(), MessageVerificationError> {
    for message in messages {
        verify_message(message)?;
    }
    Ok(())
}

pub fn parse_verified_message(value: &str) -> Result<Message, Box<dyn Error>> {
    let message = serde_json::from_str::<Message>(value)?;
    verify_message(&message)?;
    Ok(message)
}

pub fn assurance_label(message: &Message) -> String {
    match verify_single(message) {
        Ok(MessageAssurance::Verified { source, .. }) => format!("{source}/verified"),
        Ok(MessageAssurance::Attributed { source, status }) => format!("{source}/{status}"),
        Ok(MessageAssurance::NotApplicable) => "agent".to_owned(),
        Err(_) => "invalid".to_owned(),
    }
}

fn verify_single(message: &Message) -> Result<MessageAssurance, MessageVerificationError> {
    if message.direction.as_deref() != Some("boss_to_agent") {
        return Ok(MessageAssurance::NotApplicable);
    }
    let metadata = message.metadata.as_ref().ok_or_else(|| fail(message, "missing metadata"))?;
    let provenance = object(metadata.get("provenance"))
        .ok_or_else(|| fail(message, "missing provenance"))?;
    if provenance.get("version").and_then(Value::as_u64) != Some(1) {
        return Err(fail(message, "unsupported provenance version"));
    }
    let source = string(provenance, "source").ok_or_else(|| fail(message, "missing source"))?;
    if metadata.get("source").and_then(Value::as_str) != Some(source) {
        return Err(fail(message, "source attribution mismatch"));
    }
    let signature = object(provenance.get("signature"))
        .ok_or_else(|| fail(message, "missing signature state"))?;
    if signature.contains_key("scheme") {
        verify_signature(message, provenance, signature, source)
    } else {
        verify_attribution(message, signature, source)
    }
}

fn verify_attribution(
    message: &Message,
    signature: &Map<String, Value>,
    source: &str,
) -> Result<MessageAssurance, MessageVerificationError> {
    let status = string(signature, "status").ok_or_else(|| fail(message, "missing signature status"))?;
    let expected = match source {
        "discord" | "telegram" => "unsupported",
        "api" => "not_configured",
        "system" => "not_applicable",
        _ => return Err(fail(message, "unsigned native source")),
    };
    if status != expected {
        return Err(fail(message, "invalid signature status for source"));
    }
    Ok(MessageAssurance::Attributed {
        source: source.to_owned(),
        status: status.to_owned(),
    })
}

fn verify_signature(
    message: &Message,
    provenance: &Map<String, Value>,
    signature: &Map<String, Value>,
    source: &str,
) -> Result<MessageAssurance, MessageVerificationError> {
    if source != "ios" && source != "macos" {
        return Err(fail(message, "signed source is not native"));
    }
    if string(signature, "scheme") != Some(SIGNATURE_SCHEME) {
        return Err(fail(message, "unsupported signature scheme"));
    }
    let key_id = required(message, signature, "key_id")?;
    let public_key = decode_required(message, signature, "public_key")?;
    let claimed_key_id = decode(key_id).map_err(|detail| fail(message, detail))?;
    if claimed_key_id != digest(&SHA256, &public_key).as_ref() {
        return Err(fail(message, "signing key identifier mismatch"));
    }
    let compact = required(message, signature, "signed_message")?;
    let (header, payload, input, raw_signature) = parse_jws(message, compact)?;
    validate_header(message, &header, key_id)?;
    UnparsedPublicKey::new(&ECDSA_P256_SHA256_FIXED, public_key)
        .verify(input.as_bytes(), &raw_signature)
        .map_err(|_| fail(message, "invalid ES256 signature"))?;
    validate_payload(message, provenance, &payload)?;
    Ok(MessageAssurance::Verified {
        source: source.to_owned(),
        key_id: key_id.to_owned(),
    })
}

fn parse_jws(
    message: &Message,
    compact: &str,
) -> Result<(JwsHeader, SignedPayload, String, Vec<u8>), MessageVerificationError> {
    let segments: Vec<&str> = compact.split('.').collect();
    if segments.len() != 3 || segments.iter().any(|segment| segment.is_empty()) {
        return Err(fail(message, "malformed compact JWS"));
    }
    let header = decode_json(message, segments[0], "header")?;
    let payload = decode_json(message, segments[1], "payload")?;
    let signature = decode(segments[2]).map_err(|detail| fail(message, detail))?;
    if signature.len() != 64 {
        return Err(fail(message, "invalid ES256 signature length"));
    }
    Ok((header, payload, format!("{}.{}", segments[0], segments[1]), signature))
}

fn validate_header(
    message: &Message,
    header: &JwsHeader,
    key_id: &str,
) -> Result<(), MessageVerificationError> {
    if header.alg != "ES256" || header.typ != JWS_TYPE || header.kid != key_id {
        return Err(fail(message, "JWS header mismatch"));
    }
    Ok(())
}

fn validate_payload(
    message: &Message,
    provenance: &Map<String, Value>,
    payload: &SignedPayload,
) -> Result<(), MessageVerificationError> {
    if payload.version != 1 || payload.purpose != MESSAGE_PURPOSE || payload.action.kind != "reply" {
        return Err(fail(message, "signed payload contract mismatch"));
    }
    if payload.message_id.is_empty() || payload.issued_at <= 0 {
        return Err(fail(message, "invalid signed message identity"));
    }
    if message.body.as_deref() != Some(payload.body.as_str()) {
        return Err(fail(message, "signed body mismatch"));
    }
    if message.reply_to.as_deref() != Some(payload.action.message_id.as_str()) {
        return Err(fail(message, "signed reply target mismatch"));
    }
    let actor_id = object(provenance.get("actor")).and_then(|actor| string(actor, "id"));
    if actor_id != Some(payload.boss_id.as_str()) {
        return Err(fail(message, "signed boss identity mismatch"));
    }
    Ok(())
}

fn required<'a>(
    message: &Message,
    object: &'a Map<String, Value>,
    key: &str,
) -> Result<&'a str, MessageVerificationError> {
    string(object, key).ok_or_else(|| fail(message, &format!("missing {key}")))
}

fn decode_required(
    message: &Message,
    object: &Map<String, Value>,
    key: &str,
) -> Result<Vec<u8>, MessageVerificationError> {
    let encoded = required(message, object, key)?;
    decode(encoded).map_err(|detail| fail(message, detail))
}

fn decode_json<T: for<'de> Deserialize<'de>>(
    message: &Message,
    encoded: &str,
    part: &str,
) -> Result<T, MessageVerificationError> {
    let bytes = decode(encoded).map_err(|detail| fail(message, detail))?;
    serde_json::from_slice(&bytes).map_err(|_| fail(message, &format!("invalid JWS {part}")))
}

fn decode(value: &str) -> Result<Vec<u8>, &'static str> {
    if value.is_empty() || value.len() % 4 == 1 {
        return Err("invalid base64url encoding");
    }
    let mut output = Vec::with_capacity(value.len() * 3 / 4);
    let mut accumulator = 0_u32;
    let mut bits = 0_u8;
    for byte in value.bytes() {
        accumulator = (accumulator << 6) | u32::from(base64_value(byte)?);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            output.push((accumulator >> bits) as u8);
            accumulator &= (1_u32 << bits) - 1;
        }
    }
    if accumulator != 0 {
        return Err("non-canonical base64url encoding");
    }
    Ok(output)
}

fn base64_value(byte: u8) -> Result<u8, &'static str> {
    match byte {
        b'A'..=b'Z' => Ok(byte - b'A'),
        b'a'..=b'z' => Ok(byte - b'a' + 26),
        b'0'..=b'9' => Ok(byte - b'0' + 52),
        b'-' => Ok(62),
        b'_' => Ok(63),
        _ => Err("invalid base64url character"),
    }
}

fn object(value: Option<&Value>) -> Option<&Map<String, Value>> {
    value?.as_object()
}

fn string<'a>(object: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    object.get(key)?.as_str().filter(|value| !value.is_empty())
}

fn fail(message: &Message, detail: &str) -> MessageVerificationError {
    MessageVerificationError {
        message_id: message.id.clone(),
        detail: detail.to_owned(),
    }
}
