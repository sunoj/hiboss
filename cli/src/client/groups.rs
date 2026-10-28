// Purpose: Group management handlers for HiBossClient.
// Exports: list_groups, create_group, get_group, delete_group, membership, broadcast.
// Dependencies: serde_json::Value, std::error::Error, super::HiBossClient.
use super::HiBossClient;
use reqwest::Method;
use serde_json::Value;
use std::error::Error;
impl HiBossClient {
    client_endpoints! {
        list_groups() -> Value = GET "/api/groups";
        get_group(id: &str) -> Value = GET &format!("/api/groups/{}", id);
        delete_group(id: &str) -> () = DELETE_EMPTY &format!("/api/groups/{}", id), "delete failed";
        add_group_member(group_id: &str, agent_id: &str) -> Value =
            POST &format!("/api/groups/{}/members", group_id), &serde_json::json!({ "agent_id": agent_id });
        remove_group_member(group_id: &str, agent_id: &str) -> () =
            DELETE_EMPTY &format!("/api/groups/{}/members/{}", group_id, agent_id), "remove member failed";
        broadcast_to_group(group_id: &str, body: &str, priority: &str) -> Value =
            POST &format!("/api/groups/{}/broadcast", group_id),
            &serde_json::json!({ "body": body, "priority": priority });
    }
    pub async fn create_group(
        &self,
        name: &str,
        description: Option<&str>,
    ) -> Result<Value, Box<dyn Error>> {
        let mut payload = serde_json::json!({ "name": name });
        if let Some(desc) = description {
            payload["description"] = serde_json::Value::String(desc.to_owned());
        }
        Self::send_json(
            self.request(Method::POST, "/api/groups")
                .json(&payload)
        ).await
    }
}
