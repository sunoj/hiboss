// Purpose: Verify CLI enforcement of boss-message signatures before body use.
// Covers valid ES256 messages, tampering rejection, and attributed Discord input.
// Dependencies: message_security, Message API shape, ring test signing.

use crate::message_security::{verify_message, MessageAssurance};
use crate::types::Message;
use ring::digest::{digest, SHA256};
use ring::rand::SystemRandom;
use ring::signature::{
    EcdsaKeyPair, KeyPair, ECDSA_P256_SHA256_FIXED_SIGNING,
};
use serde_json::json;

#[test]
fn verifies_signed_ios_reply() {
    let message = signed_message("Approved", "Approved");
    assert!(matches!(
        verify_message(&message),
        Ok(MessageAssurance::Verified { source, .. }) if source == "ios"
    ));
}

#[test]
fn rejects_body_tampering_before_use() {
    let message = signed_message("Approved", "Changed after signing");
    let error = verify_message(&message).expect_err("tampering must fail");
    assert!(error.to_string().contains("body"));
}

#[test]
fn accepts_discord_with_explicit_unsupported_attribution() {
    let metadata = serde_json::from_value(json!({
        "source": "discord",
        "provenance": {
            "version": 1,
            "source": "discord",
            "signature": { "status": "unsupported" }
        }
    }))
    .expect("metadata");
    let message = base_message("Discord command", metadata);
    assert!(matches!(
        verify_message(&message),
        Ok(MessageAssurance::Attributed { source, status })
            if source == "discord" && status == "unsupported"
    ));
}

#[test]
fn form_answers_must_be_the_signed_answers() {
    let answers = json!({"order": ["b", "a"]});
    let signed = signed_form(Some(answers.clone()), Some(answers.clone()));
    assert!(verify_message(&signed).is_ok(), "stored answers equal the signed answers");
    let swapped = signed_form(Some(answers.clone()), Some(json!({"order": ["a", "b"]})));
    assert!(verify_message(&swapped).is_err(), "answers changed after signing");
    let float = signed_form(Some(json!({"score": 1.0})), Some(json!({"score": 1})));
    assert!(verify_message(&float).is_ok(), "1.0 signed and 1 stored are the same answer");
    let unsigned = signed_form(None, Some(answers));
    assert!(verify_message(&unsigned).is_err(), "answers added to a reply that signed none");
}

fn signed_form(signed: Option<serde_json::Value>, stored: Option<serde_json::Value>) -> Message {
    let mut message = signed_message_with("Submitted", "Submitted", signed);
    if let (Some(metadata), Some(stored)) = (message.metadata.as_mut(), stored) {
        metadata.insert("answers".to_owned(), stored);
    }
    message
}

fn signed_message(signed_body: &str, outer_body: &str) -> Message {
    signed_message_with(signed_body, outer_body, None)
}

fn signed_message_with(
    signed_body: &str, outer_body: &str, answers: Option<serde_json::Value>,
) -> Message {
    let rng = SystemRandom::new();
    let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_FIXED_SIGNING, &rng)
        .expect("test key");
    let key = EcdsaKeyPair::from_pkcs8(
        &ECDSA_P256_SHA256_FIXED_SIGNING, pkcs8.as_ref(), &rng,
    )
    .expect("parse key");
    let key_id = encode(digest(&SHA256, key.public_key().as_ref()).as_ref());
    let header = encode_json(&json!({
        "alg": "ES256", "kid": key_id, "typ": "hiboss-message+jws"
    }));
    let mut payload = json!({
        "version": 1,
        "purpose": "hiboss.boss-message",
        "message_id": "12345678-1234-1234-1234-123456789abc",
        "issued_at": 1_788_454_800_i64,
        "boss_id": "boss-1",
        "action": { "kind": "reply", "message_id": "parent-1" },
        "body": signed_body
    });
    if let Some(answers) = answers { payload["answers"] = answers; }
    let payload = encode_json(&payload);
    let input = format!("{header}.{payload}");
    let signature = key.sign(&rng, input.as_bytes()).expect("sign");
    let compact = format!("{input}.{}", encode(signature.as_ref()));
    let metadata = serde_json::from_value(json!({
        "source": "ios",
        "boss_id": "boss-1",
        "provenance": {
            "version": 1,
            "source": "ios",
            "actor": { "kind": "boss", "id": "boss-1" },
            "signature": {
                "scheme": "JWS-ES256",
                "key_id": key_id,
                "public_key": encode(key.public_key().as_ref()),
                "signed_message": compact
            }
        }
    }))
    .expect("metadata");
    base_message(outer_body, metadata)
}

fn base_message(
    body: &str,
    metadata: std::collections::HashMap<String, serde_json::Value>,
) -> Message {
    Message {
        direction: Some("boss_to_agent".to_owned()),
        mode: Some("async".to_owned()),
        channel: Some("api".to_owned()),
        body: Some(body.to_owned()),
        status: Some("sent".to_owned()),
        reply_to: Some("parent-1".to_owned()),
        priority: Some("normal".to_owned()),
        message_type: Some("text".to_owned()),
        metadata: Some(metadata),
        ..crate::tests::message("reply-1".to_owned())
    }
}

fn encode_json(value: &serde_json::Value) -> String {
    encode(serde_json::to_string(value).expect("json").as_bytes())
}

fn encode(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut output = String::new();
    for chunk in bytes.chunks(3) {
        let value = chunk.iter().fold(0_u32, |acc, byte| (acc << 8) | u32::from(*byte));
        let shifted = value << (8 * (3 - chunk.len()));
        for index in 0..(chunk.len() + 1) {
            output.push(ALPHABET[((shifted >> (18 - index * 6)) & 63) as usize] as char);
        }
    }
    output
}
