// Purpose: Boss management client methods for hiboss CLI.
// Exports: Boss-related methods on HiBossClient (list, create, update, delete, access).
// Dependencies: reqwest, serde_json, crate::client::HiBossClient.

use super::HiBossClient;
use serde_json::Value;
use std::error::Error;

impl HiBossClient {
    pub async fn list_bosses(&self) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/bosses", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn create_boss(&self, body: &Value) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/bosses", self.base_url))
            .bearer_auth(&self.api_key)
            .json(body)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn get_boss(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/bosses/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn update_boss(&self, id: &str, body: &Value) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .patch(format!("{}/api/bosses/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(body)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn delete_boss(&self, id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self
            .http
            .delete(format!("{}/api/bosses/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        if resp.status().is_success() {
            Ok(())
        } else {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            Err(format!("request failed ({}): {}", status, body).into())
        }
    }
    pub async fn grant_boss_access(
        &self,
        boss_id: &str,
        agent_id: &str,
    ) -> Result<(), Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/bosses/{}/access", self.base_url, boss_id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "agent_id": agent_id }))
            .send()
            .await?;
        if resp.status().is_success() {
            Ok(())
        } else {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            Err(format!("request failed ({}): {}", status, body).into())
        }
    }
    pub async fn revoke_boss_access(
        &self,
        boss_id: &str,
        agent_id: &str,
    ) -> Result<(), Box<dyn Error>> {
        let resp = self
            .http
            .delete(format!(
                "{}/api/bosses/{}/access/{}",
                self.base_url, boss_id, agent_id
            ))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        if resp.status().is_success() {
            Ok(())
        } else {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            Err(format!("request failed ({}): {}", status, body).into())
        }
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
        Self::parse_response(resp).await
    }
    pub async fn boss_read(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/boss/inbox/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn boss_reply(&self, id: &str, body: &str) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/boss/inbox/{}/reply", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "body": body }))
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
