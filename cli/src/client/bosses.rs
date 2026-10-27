// Purpose: Boss management client methods for hiboss CLI.
// Exports: Boss-related methods on HiBossClient (list, update, delete, access, verified inbox reads).
// Dependencies: reqwest, serde_json, crate::client::HiBossClient.

use super::HiBossClient;
use reqwest::Method;
use serde_json::Value;
use std::error::Error;

impl HiBossClient {
    pub async fn list_agent_bosses(&self) -> Result<Value, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, "/api/agents/me/bosses")).await
    }

    pub async fn list_bosses(&self) -> Result<Value, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, "/api/bosses")).await
    }
    pub async fn get_boss(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, &format!("/api/bosses/{}", id))).await
    }
    pub async fn update_boss(&self, id: &str, body: &Value) -> Result<Value, Box<dyn Error>> {
        Self::send_json(
            self.request(Method::PATCH, &format!("/api/bosses/{}", id))
                .json(body),
        )
        .await
    }
    pub async fn archive_boss(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        Self::send_json(self.request(Method::POST, &format!("/api/bosses/{}/archive", id))).await
    }
    pub async fn restore_boss(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        Self::send_json(self.request(Method::POST, &format!("/api/bosses/{}/restore", id))).await
    }
    pub async fn delete_boss(&self, id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self
            .request(Method::DELETE, &format!("/api/bosses/{}", id))
            .send()
            .await?;
        Self::empty_response(resp, "request failed").await
    }
    pub async fn grant_boss_access(&self, boss_id: &str, agent_id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self
            .request(Method::POST, &format!("/api/bosses/{}/access", boss_id))
            .json(&serde_json::json!({ "agent_id": agent_id }))
            .send()
            .await?;
        Self::empty_response(resp, "request failed").await
    }
    pub async fn revoke_boss_access(&self, boss_id: &str, agent_id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self
            .request(
                Method::DELETE,
                &format!("/api/bosses/{}/access/{}", boss_id, agent_id),
            )
            .send()
            .await?;
        Self::empty_response(resp, "request failed").await
    }
    pub async fn boss_inbox(
        &self,
        unread: bool,
        limit: u32,
        priority: Option<&str>,
        count_only: bool,
    ) -> Result<Value, Box<dyn Error>> {
        let mut request = self
            .http
            .get(format!("{}/api/boss/inbox", self.base_url))
            .bearer_auth(&self.api_key)
            .query(&[("limit", limit.to_string())]);
        if unread {
            request = request.query(&[("unread", "true")]);
        }
        if let Some(p) = priority {
            request = request.query(&[("priority", p)]);
        }
        if count_only {
            request = request.query(&[("count", "true")]);
        }
        let resp = request.send().await?;
        verified_rows(Self::parse_response(resp).await?)
    }
    pub async fn boss_read(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/boss/inbox/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        verified_rows(Self::parse_response(resp).await?)
    }
    pub async fn boss_reply(&self, id: &str, body: &str) -> Result<Value, Box<dyn Error>> {
        let mut id = id.to_owned();
        if self.signer()?.is_some() {
            let parent = self.boss_read(&id).await?;
            id = parent.get("id").and_then(Value::as_str).ok_or("boss inbox returned no message ID")?.to_owned();
        }
        let request = self.signed_body(
            serde_json::json!({ "body": body }),
            serde_json::json!({ "kind": "boss_reply", "message_id": id }),
        )?;
        let resp = self
            .http
            .post(format!("{}/api/boss/inbox/{}/reply", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&request)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn boss_mark_read(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .patch(format!("{}/api/boss/inbox/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "status": "read" }))
            .send()
            .await?;
        Self::parse_response(resp).await
    }
}

/// A boss-agent hands these bodies to a model: verify every row (and its replies) first.
fn verified_rows(value: Value) -> Result<Value, Box<dyn Error>> {
    let rows = match value.get("messages") {
        Some(Value::Array(items)) => items.clone(),
        _ if value.get("id").is_some() => vec![value.clone()],
        _ => Vec::new(),
    };
    for row in rows {
        let message: crate::types::Message = serde_json::from_value(row)?;
        crate::message_security::verify_message(&message)?;
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::verified_rows;
    use serde_json::json;

    #[test]
    fn boss_inbox_rows_are_verified_before_use() {
        let forged = json!({"messages": [{"id": "m1", "agent_id": "a1", "direction": "agent_to_boss", "body": "hi",
            "metadata": {"source": "ios", "provenance": {"version": 1, "source": "ios",
                "signature": {"status": "not_configured"}}}}], "total": 1});
        assert!(verified_rows(forged).is_err());
        let legacy = json!({"messages": [{"id": "m1", "agent_id": "a1", "direction": "agent_to_boss", "body": "hi"}], "total": 1});
        assert!(verified_rows(legacy).is_ok());
        assert!(verified_rows(json!({"total": 3})).is_ok());
    }
}
