// Purpose: Build signed request bodies for HiBossClient writes once this credential is enrolled.
// Exports: signer, signed_body, signed_send_body, signed_reply, signed_forward.
// Dependencies: crate::signing, crate::types, serde_json; see docs/agent-message-signing.md.

use super::HiBossClient;
use crate::types::{Message, SendRequest};
use serde_json::{Value, json};
use std::error::Error;

impl HiBossClient {
    /// The enrolled signing key for this credential; None until `hiboss key enroll` ran here.
    pub(crate) fn signer(&self) -> Result<Option<crate::signing::AgentSigner>, Box<dyn Error>> {
        crate::signing::load_signer(&self.api_key)
    }

    /// Attaches `signed_message` for `action` when this credential has an enrolled key.
    pub(crate) fn signed_body(&self, mut body: Value, action: Value) -> Result<Value, Box<dyn Error>> {
        if let (Some(signer), Some(fields)) = (self.signer()?, body.as_object_mut()) {
            crate::signing::sign_action(&signer, fields, action)?;
        }
        Ok(body)
    }

    /// A send names its resolved recipient, so a stored peer row cannot be re-addressed.
    pub(crate) async fn signed_send_body(&self, req: &SendRequest) -> Result<Value, Box<dyn Error>> {
        let mut body = serde_json::to_value(req)?;
        let Some(signer) = self.signer()? else { return Ok(body) };
        let to = req.to.as_deref().map(str::trim).filter(|to| !to.is_empty());
        let audience = match to {
            Some(to) => self.resolve_audience(to, req.session_id.as_deref()).await?,
            None => json!({ "kind": "boss" }),
        };
        if let Some(fields) = body.as_object_mut() {
            crate::signing::sign_send(&signer, fields, audience)?;
        }
        Ok(body)
    }

    async fn resolve_audience(&self, to: &str, session_id: Option<&str>) -> Result<Value, Box<dyn Error>> {
        let resp = self.http.post(format!("{}/api/messages/resolve-target", self.base_url))
            .bearer_auth(&self.api_key)
            .json(&json!({ "to": to, "session_id": session_id }))
            .send().await?;
        let target: Value = Self::parse_response(resp).await?;
        let agent_id = target.get("agent_id").and_then(Value::as_str).ok_or("target resolution returned no agent")?;
        Ok(json!({ "kind": "agent", "agent_id": agent_id, "session_id": target.get("session_id").cloned().unwrap_or(Value::Null) }))
    }

    /// Signs over the full parent ID and the recipient the server derives from the parent.
    pub(crate) async fn signed_reply(&self, id: &str, body: &str) -> Result<(String, Value), Box<dyn Error>> {
        let request = json!({ "body": body });
        if self.signer()?.is_none() {
            return Ok((id.to_owned(), request));
        }
        let parent = self.get_message(id).await?;
        let audience = reply_audience(&parent);
        let signed = self.signed_body(request, json!({ "kind": "reply", "message_id": parent.id, "audience": audience }))?;
        Ok((parent.id, signed))
    }

    pub(crate) async fn signed_forward(&self, id: &str, channel: &str) -> Result<(String, Value), Box<dyn Error>> {
        let request = json!({ "channel": channel });
        if self.signer()?.is_none() {
            return Ok((id.to_owned(), request));
        }
        let full = self.get_message(id).await?.id;
        let signed = self.signed_body(request, json!({ "kind": "forward", "message_id": full, "channel": channel }))?;
        Ok((full, signed))
    }
}

/// Mirrors the server: a reply to a peer message goes back to its sender, otherwise to the boss.
fn reply_audience(parent: &Message) -> Value {
    if parent.direction.as_deref() != Some("agent_to_agent") {
        return json!({ "kind": "boss" });
    }
    let session = parent.session_id.clone().or_else(|| parent.target_session_id.clone());
    json!({ "kind": "agent", "agent_id": parent.agent_id, "session_id": session })
}
