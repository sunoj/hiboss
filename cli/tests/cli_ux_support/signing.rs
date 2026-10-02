// Purpose: Build a native-signed boss reply fixture with a fresh ephemeral ES256 key.
// Exports: signed_reply(). Mirrors the signing pattern in src/message_security_tests.rs;
// no key leaves the process. Dependencies: ring, serde_json.

use ring::digest::{SHA256, digest};
use ring::rand::SystemRandom;
use ring::signature::{ECDSA_P256_SHA256_FIXED_SIGNING, EcdsaKeyPair, KeyPair};
use serde_json::{Value, json};

/// A `boss_to_agent` iOS reply to `parent` whose JWS covers `body`.
pub fn signed_reply(id: &str, parent: &str, body: &str) -> Value {
    let rng = SystemRandom::new();
    let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_FIXED_SIGNING, &rng)
        .expect("ephemeral test key");
    let key = EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_FIXED_SIGNING, pkcs8.as_ref(), &rng)
        .expect("parse test key");
    let key_id = encode(digest(&SHA256, key.public_key().as_ref()).as_ref());
    let header = encode_json(&json!({"alg": "ES256", "kid": key_id, "typ": "hiboss-message+jws"}));
    let payload = encode_json(&json!({
        "version": 1, "purpose": "hiboss.boss-message", "message_id": id,
        "issued_at": 1_788_454_800_i64, "boss_id": "boss-1",
        "action": {"kind": "reply", "message_id": parent}, "body": body,
    }));
    let input = format!("{header}.{payload}");
    let signature = key.sign(&rng, input.as_bytes()).expect("sign");
    let signature = json!({
        "scheme": "JWS-ES256", "key_id": key_id,
        "public_key": encode(key.public_key().as_ref()),
        "signed_message": format!("{input}.{}", encode(signature.as_ref())),
    });
    let provenance = json!({"version": 1, "source": "ios",
        "actor": {"kind": "boss", "id": "boss-1"}, "signature": signature});
    json!({"id": id, "direction": "boss_to_agent", "status": "sent", "body": body,
        "reply_to": parent, "metadata": {"source": "ios", "boss_id": "boss-1",
        "provenance": provenance}})
}

fn encode_json(value: &Value) -> String {
    encode(value.to_string().as_bytes())
}

/// Unpadded base64url, the encoding the verifier requires.
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
