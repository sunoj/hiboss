// Purpose: Enroll a credential's signing key with the server (first use or endorsed).
// Exports: Enrollment, enroll.
// Dependencies: reqwest, serde_json, the local key store and compact JWS encoding.

use super::{jws::{compact, encode}, payload::now, store};
use serde::Deserialize;
use serde_json::json;
use std::{error::Error, time::Duration};

const KEY_DOMAIN: &str = "hiboss-agent-key-v1";
const ENDORSEMENT_TYPE: &str = "hiboss-agent-key+jws";

#[derive(Deserialize)]
struct Identity {
    id: String,
    agent_key_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct Enrollment {
    pub key_id: String,
    pub fingerprint: String,
    pub enrolled_via: String,
    #[serde(skip)]
    pub created: bool,
}

/// Binds this credential's key, endorsed by `endorser` when the agent already signs elsewhere.
pub async fn enroll(
    server: &str,
    bearer: &str,
    endorser: Option<&store::AgentSigner>,
) -> Result<Enrollment, Box<dyn Error>> {
    let http = reqwest::Client::builder().timeout(Duration::from_secs(30)).build()?;
    let base = server.trim_end_matches('/');
    let identity: Identity = http.get(format!("{base}/api/agents/me")).bearer_auth(bearer)
        .send().await?.error_for_status()?.json().await?;
    let agent_key_id = identity.agent_key_id
        .ok_or("this credential predates per-device keys; run `hiboss key rotate` first")?;
    let signer = match store::load_signer(bearer)? {
        Some(signer) => signer,
        None => store::load_or_create_pending(bearer, &identity.id, &agent_key_id)?,
    };
    let proof_input = format!("{KEY_DOMAIN}\n{agent_key_id}\n{}\n{}", identity.id, signer.public_key);
    let mut body = json!({ "public_key": signer.public_key, "proof": encode(&signer.sign(proof_input.as_bytes())?) });
    if let Some(endorser) = endorser {
        let endorsement = json!({
            "version": 1, "purpose": "hiboss.agent-key-endorsement", "agent_id": identity.id,
            "agent_key_id": agent_key_id, "key_id": signer.key_id, "issued_at": now()?,
        });
        body["endorsement"] = json!(compact(endorser, ENDORSEMENT_TYPE, &endorsement)?);
    }
    let response = http.post(format!("{base}/api/agents/me/signing-keys")).bearer_auth(bearer)
        .json(&body).send().await?;
    let status = response.status();
    if !status.is_success() {
        let detail = response.text().await.unwrap_or_default();
        return Err(match status.as_u16() {
            403 => format!("enrollment refused: {detail}"),
            409 => format!("enrollment conflict: {detail}. If this device lost its key, ask the boss to reset this agent's signing keys"),
            _ => format!("enrollment failed ({status}): {detail}"),
        }.into());
    }
    let mut enrollment: Enrollment = response.json().await?;
    enrollment.created = status.as_u16() == 201;
    if store::load_signer(bearer)?.is_none() {
        store::commit_pending(bearer)?;
    }
    Ok(enrollment)
}
