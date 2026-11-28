// The shareable boss key text: `hiboss-boss-key:` + base64url(JSON {boss_id, key_id, public_key, client_kind, label}).
// The app shows it; `hiboss boss trust` and `hiboss boss keys` read and print it.
// Exports BossKeyText, parse, render, decode. Dependencies: serde_json, ring SHA-256, signing::jws::encode.

use ring::digest::{digest, SHA256};
use serde::{Deserialize, Serialize};

const PREFIX: &str = "hiboss-boss-key:";

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct BossKeyText {
    pub boss_id: String,
    pub key_id: String,
    pub public_key: String,
    pub client_kind: String,
    #[serde(default)]
    pub label: Option<String>,
}

/// Parses and checks the text: the key id must be the SHA-256 of the 65-byte P-256 public key.
pub fn parse(text: &str) -> Result<BossKeyText, String> {
    let body = text.trim().strip_prefix(PREFIX).ok_or("not a HiBoss boss key (expected hiboss-boss-key:…)")?;
    let json = decode(body).ok_or("the key text is not valid base64url")?;
    let key: BossKeyText = serde_json::from_slice(&json).map_err(|error| format!("the key text is not valid: {error}"))?;
    let public_key = decode(&key.public_key).ok_or("the public key is not valid base64url")?;
    if public_key.len() != 65 || public_key[0] != 4 {
        return Err("the public key is not an uncompressed P-256 key".to_owned());
    }
    if crate::signing::jws::encode(digest(&SHA256, &public_key).as_ref()) != key.key_id {
        return Err("the key id does not match the public key".to_owned());
    }
    if !matches!(key.client_kind.as_str(), "ios" | "macos" | "web") {
        return Err(format!("unknown client kind {:?}", key.client_kind));
    }
    Ok(key)
}

pub fn render(key: &BossKeyText) -> String {
    let json = serde_json::to_vec(key).unwrap_or_default();
    format!("{PREFIX}{}", crate::signing::jws::encode(&json))
}

/// Base64url without padding; None for anything else.
pub fn decode(value: &str) -> Option<Vec<u8>> {
    crate::message_security::decode(value).ok()
}
