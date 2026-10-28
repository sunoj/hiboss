// Purpose: Routing rule management for HiBossClient.
// Exports: list_routing_rules, create_routing_rule, delete_routing_rule.
// Dependencies: serde_json::Value, super::HiBossClient, client_endpoints macro.
use super::HiBossClient;
use serde_json::Value;
impl HiBossClient {
    client_endpoints! {
        list_routing_rules() -> Value = GET "/api/routing-rules";
        create_routing_rule(channel: &str, pattern: &str, target: &str, priority: i32) -> Value =
            POST "/api/routing-rules",
            &serde_json::json!({
                "channel": channel,
                "pattern": pattern,
                "target_agent_id": target,
                "priority": priority,
            });
        delete_routing_rule(id: &str) -> () =
            DELETE_EMPTY &format!("/api/routing-rules/{}", id), "delete failed";
    }
}
