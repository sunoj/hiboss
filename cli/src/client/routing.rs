// Purpose: Routing rule management for HiBossClient.
// Exports: list_routing_rules, create_routing_rule, delete_routing_rule.
// Dependencies: serde_json::Value, std::error::Error, super::HiBossClient.
use super::HiBossClient;
use reqwest::Method;
use serde_json::Value;
use std::error::Error;
impl HiBossClient {
    pub async fn list_routing_rules(&self) -> Result<Value, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, "/api/routing-rules")).await
    }
    pub async fn create_routing_rule(
        &self,
        channel: &str,
        pattern: &str,
        target: &str,
        priority: i32,
    ) -> Result<Value, Box<dyn Error>> {
        Self::send_json(
            self.request(Method::POST, "/api/routing-rules")
                .json(&serde_json::json!({
                    "channel": channel, "pattern": pattern,
                    "target_agent_id": target, "priority": priority,
                }))
        ).await
    }
    pub async fn delete_routing_rule(&self, id: &str) -> Result<(), Box<dyn Error>> {
        self.delete(&format!("/api/routing-rules/{}", id), "delete failed")
            .await
    }
}
