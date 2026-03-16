// Purpose: Routing rule management for HiBossClient.
// Exports: list_routing_rules, create_routing_rule, delete_routing_rule.
// Dependencies: serde_json::Value, std::error::Error, super::HiBossClient.
use serde_json::Value;
use std::error::Error;
use super::HiBossClient;
impl HiBossClient {
    pub async fn list_routing_rules(&self) -> Result<Value, Box<dyn Error>> {
        let resp = self.http.get(format!("{}/api/routing-rules", self.base_url))
            .bearer_auth(&self.api_key).send().await?;
        Self::parse_response(resp).await
    }
    pub async fn create_routing_rule(&self, channel: &str, pattern: &str, target: &str, priority: i32) -> Result<Value, Box<dyn Error>> {
        let resp = self.http.post(format!("{}/api/routing-rules", self.base_url))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "channel": channel, "pattern": pattern, "target_agent_id": target, "priority": priority }))
            .send().await?;
        Self::parse_response(resp).await
    }
    pub async fn delete_routing_rule(&self, id: &str) -> Result<(), Box<dyn Error>> {
        let resp = self.http.delete(format!("{}/api/routing-rules/{}", self.base_url, id))
            .bearer_auth(&self.api_key).send().await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("delete failed ({}): {}", status, body).into());
        }
        Ok(())
    }
}
