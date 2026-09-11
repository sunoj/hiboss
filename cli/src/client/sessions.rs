// Session registration, discovery and heartbeat HTTP methods.
// Exports HiBossClient session methods; depends on reqwest and project resolution.
use super::{HiBossClient, format_http_error};
use std::error::Error;
use serde_json::Value;

impl HiBossClient {
    pub async fn register_session(
        &self,
        id: &str,
        branch: Option<&str>,
        cwd: Option<&str>,
        label: Option<&str>,
        status: Option<&str>,
        status_text: Option<&str>,
    ) -> Result<(), Box<dyn Error>> {
        let mut body = serde_json::json!({ "id": id, "project": crate::session::resolve_project(None) });
        if let Some(b) = branch {
            body["branch"] = serde_json::Value::String(b.to_owned());
        }
        if let Some(c) = cwd {
            body["cwd"] = serde_json::Value::String(c.to_owned());
        }
        if let Some(l) = label {
            body["label"] = serde_json::Value::String(l.to_owned());
        }
        if let Some(s) = status {
            body["status"] = serde_json::Value::String(s.to_owned());
        }
        if let Some(t) = status_text {
            body["status_text"] = serde_json::Value::String(t.to_owned());
        }
        let resp = self
            .http
            .post(format!("{}/api/sessions", self.base_url))
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let req_id = resp
                .headers()
                .get("x-request-id")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string());
            let text = resp.text().await.unwrap_or_default();
            return Err(format_http_error("session register failed", status, req_id, text).into());
        }
        Ok(())
    }
    pub async fn list_sessions(&self) -> Result<crate::types::SessionsResponse, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/sessions?all=true", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn heartbeat_session(
        &self,
        id: &str,
        status: Option<&str>,
        status_text: Option<&str>,
    ) -> Result<(), Box<dyn Error>> {
        let mut req = self
            .http
            .patch(format!("{}/api/sessions/{}", self.base_url, id))
            .bearer_auth(&self.api_key);
        if status.is_some() || status_text.is_some() {
            let mut body = serde_json::Map::new();
            if let Some(s) = status {
                body.insert("status".into(), serde_json::Value::String(s.to_owned()));
            }
            if let Some(t) = status_text {
                body.insert(
                    "status_text".into(),
                    serde_json::Value::String(t.to_owned()),
                );
            }
            req = req.json(&body);
        }
        let resp = req.send().await?;
        if !resp.status().is_success() { /* ignore heartbeat failures */ }
        Ok(())
    }
    pub async fn mark_all_read(&self) -> Result<u32, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/messages/mark-all-read", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        let data: Value = Self::parse_response(resp).await?;
        Ok(data["marked"].as_u64().unwrap_or(0) as u32)
    }
}
