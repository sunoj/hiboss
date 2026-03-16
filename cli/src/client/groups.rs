// Purpose: Group management handlers for HiBossClient.
// Exports: list_groups, create_group, get_group, delete_group, membership, broadcast.
// Dependencies: serde_json::Value, std::error::Error, super::HiBossClient.
use serde_json::Value;
use std::error::Error;
use super::HiBossClient;
impl HiBossClient {
    pub async fn list_groups(&self) -> Result<Value, Box<dyn Error>> {
        let resp = self.http.get(format!("{}/api/groups", self.base_url))
            .bearer_auth(&self.api_key).send().await?;
        Self::parse_response(resp).await
    }
    pub async fn create_group(&self, name: &str, description: Option<&str>) -> Result<Value, Box<dyn Error>> {
        let mut payload = serde_json::json!({ "name": name });
        if let Some(desc) = description {
            payload["description"] = serde_json::Value::String(desc.to_owned());
        }
        let resp = self.http.post(format!("{}/api/groups", self.base_url))
            .bearer_auth(&self.api_key)
            .json(&payload)
            .send().await?;
        Self::parse_response(resp).await
    }
    pub async fn get_group(&self, id: &str) -> Result<Value, Box<dyn Error>> {
        let resp = self.http.get(format!("{}/api/groups/{}", self.base_url, id))
            .bearer_auth(&self.api_key).send().await?;
        Self::parse_response(resp).await
    }
    pub async fn delete_group(&self, id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self.http.delete(format!("{}/api/groups/{}", self.base_url, id))
            .bearer_auth(&self.api_key).send().await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("delete failed ({}): {}", status, body).into());
        }
        Ok(())
    }
    pub async fn add_group_member(&self, group_id: &str, agent_id: &str) -> Result<Value, Box<dyn Error>> {
        let resp = self.http.post(format!("{}/api/groups/{}/members", self.base_url, group_id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "agent_id": agent_id }))
            .send().await?;
        Self::parse_response(resp).await
    }
    pub async fn remove_group_member(&self, group_id: &str, agent_id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self.http.delete(format!("{}/api/groups/{}/members/{}", self.base_url, group_id, agent_id))
            .bearer_auth(&self.api_key).send().await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("remove member failed ({}): {}", status, body).into());
        }
        Ok(())
    }
    pub async fn broadcast_to_group(&self, group_id: &str, body: &str, priority: &str) -> Result<Value, Box<dyn Error>> {
        let resp = self.http.post(format!("{}/api/groups/{}/broadcast", self.base_url, group_id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "body": body, "priority": priority }))
            .send().await?;
        Self::parse_response(resp).await
    }
}
