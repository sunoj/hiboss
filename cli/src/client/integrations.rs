// Purpose: Integration and webhook URL management handlers for HiBossClient (admin agents only).
// Exports: create_integration, list_integrations, add_webhook, rotate_webhook, revoke_webhook.
// Dependencies: serde_json::Value, std::error::Error, super::HiBossClient.
use super::HiBossClient;
use serde_json::Value;
impl HiBossClient {
    client_endpoints! {
        create_integration(name: &str, priority: &str) -> Value =
            POST "/api/integrations", &serde_json::json!({ "name": name, "priority_cap": priority });
        list_integrations() -> Value = GET "/api/integrations";
        add_webhook(agent_id: &str, label: &str, priority: &str) -> Value =
            POST &format!("/api/integrations/{}/webhooks", agent_id),
            &serde_json::json!({ "label": label, "priority_cap": priority });
        rotate_webhook(id: &str) -> Value =
            POST &format!("/api/integrations/webhooks/{}/rotate", id), &serde_json::json!({});
        revoke_webhook(id: &str) -> () =
            DELETE_EMPTY &format!("/api/integrations/webhooks/{}", id), "revoke failed";
    }
}

#[cfg(test)]
mod tests {
    use super::super::test_http::{Http, Response};
    use super::HiBossClient;
    use serde_json::json;

    #[tokio::test]
    async fn integration_endpoints_use_the_admin_routes_and_bodies() {
        let server = Http::start(|request| {
            if request.method == "DELETE" { Response::json(204, json!(null)) }
            else { Response::json(200, json!({"url": "https://hiboss.test/api/webhooks/1/t"})) }
        });
        let client = HiBossClient::new(&server.url, "admin-key");
        client.create_integration("Grafana prod", "low").await.unwrap();
        client.list_integrations().await.unwrap();
        client.add_webhook("agent-1", "staging", "high").await.unwrap();
        client.rotate_webhook("1234567890123456789").await.unwrap();
        client.revoke_webhook("1234567890123456789").await.unwrap();
        let requests = server.requests();
        let calls: Vec<(&str, &str)> = requests.iter().map(|r| (r.method.as_str(), r.path.as_str())).collect();
        assert_eq!(calls, vec![
            ("POST", "/api/integrations"),
            ("GET", "/api/integrations"),
            ("POST", "/api/integrations/agent-1/webhooks"),
            ("POST", "/api/integrations/webhooks/1234567890123456789/rotate"),
            ("DELETE", "/api/integrations/webhooks/1234567890123456789"),
        ]);
        assert_eq!(requests[0].body, json!({"name": "Grafana prod", "priority_cap": "low"}));
        assert_eq!(requests[2].body, json!({"label": "staging", "priority_cap": "high"}));
        assert_eq!(requests[0].header("authorization"), Some("Bearer admin-key"));
    }
}
