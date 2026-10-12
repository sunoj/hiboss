// Purpose: Encode base64url and build compact ES256 JWS tokens for agent signing.
// Exports: encode, compact.
// Dependencies: serde_json and the AgentSigner in this module.

use super::store::AgentSigner;
use serde_json::{Value, json};
use std::error::Error;

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// Unpadded base64url, the encoding every JWS segment and key field uses.
pub fn encode(bytes: &[u8]) -> String {
    let mut output = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let value = chunk
            .iter()
            .enumerate()
            .fold(0_u32, |acc, (index, byte)| acc | u32::from(*byte) << (16 - 8 * index));
        for index in 0..=chunk.len() {
            output.push(char::from(ALPHABET[((value >> (18 - 6 * index)) & 63) as usize]));
        }
    }
    output
}

/// `base64url(header).base64url(payload).base64url(signature)` with `kid` = the signer's key ID.
pub fn compact(signer: &AgentSigner, typ: &str, payload: &Value) -> Result<String, Box<dyn Error>> {
    let header = json!({ "alg": "ES256", "kid": signer.key_id, "typ": typ });
    let input = format!(
        "{}.{}",
        encode(&serde_json::to_vec(&header)?),
        encode(&serde_json::to_vec(payload)?)
    );
    let signature = signer.sign(input.as_bytes())?;
    Ok(format!("{input}.{}", encode(&signature)))
}

#[cfg(test)]
mod tests {
    use super::encode;

    #[test]
    fn encodes_unpadded_base64url() {
        assert_eq!(encode(b""), "");
        assert_eq!(encode(b"f"), "Zg");
        assert_eq!(encode(b"fo"), "Zm8");
        assert_eq!(encode(b"foo"), "Zm9v");
        assert_eq!(encode(&[0xfb, 0xff]), "-_8");
    }
}
