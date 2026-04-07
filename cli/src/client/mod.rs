// Purpose: Define HiBossClient plus messaging, admin, and upload helpers.
// Exports: HiBossClient struct, core messaging + admin methods, upload and helpers.
// Dependencies: reqwest, serde_json, crate::types, std::error::Error.
use crate::types::{AgentsResponse, ChannelStatsResponse, ChannelsResponse, CreateAgentResponse, ReactionsResponse, SendRequest, SendResponse, UploadResponse};
use reqwest::Client;
use serde_json::Value;
use std::error::Error;
use std::time::Duration;
fn mime_from_ext(filename: &str) -> String {
    let ext = filename.rsplit('.').next().unwrap_or("").to_lowercase();
    match ext.as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "pdf" => "application/pdf",
        "json" => "application/json",
        "txt" | "log" => "text/plain",
        "html" | "htm" => "text/html",
        "css" => "text/css",
        "js" => "application/javascript",
        "zip" => "application/zip",
        "tar" => "application/x-tar",
        "gz" => "application/gzip",
        _ => "application/octet-stream",
    }
    .to_owned()
}
pub struct HiBossClient {
    base_url: String,
    api_key: String,
    http: Client,
    poll_http: Client,
}
impl HiBossClient {
    pub fn new(server: &str, key: &str) -> Self {
        let trimmed = server.trim_end_matches('/');
        Self {
            base_url: trimmed.to_owned(),
            api_key: key.to_owned(),
            http: Client::builder()
                .connect_timeout(Duration::from_secs(10))
                .timeout(Duration::from_secs(30))
                .build()
                .expect("failed to build HTTP client"),
            poll_http: Client::builder()
                .connect_timeout(Duration::from_secs(10))
                .timeout(Duration::from_secs(120))
                .build()
                .expect("failed to build HTTP client"),
        }
    }
    pub async fn send_message(&self, req: &SendRequest) -> Result<SendResponse, Box<dyn Error>> {
        let resp = self.http
            .post(format!("{}/api/messages", self.base_url))
            .bearer_auth(&self.api_key)
            .json(req)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn create_agent(&self, name: &str) -> Result<CreateAgentResponse, Box<dyn Error>> {
        let resp = self.http
            .post(format!("{}/api/keys", self.base_url))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "name": name }))
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn list_agents(&self) -> Result<AgentsResponse, Box<dyn Error>> {
        let resp = self.http
            .get(format!("{}/api/agents", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn set_channel(&self, channel: &str, config: &Value) -> Result<Value, Box<dyn Error>> {
        let resp = self.http
            .put(format!("{}/api/channels/{}", self.base_url, channel))
            .bearer_auth(&self.api_key)
            .json(config)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn list_channels(&self) -> Result<ChannelsResponse, Box<dyn Error>> {
        let resp = self.http
            .get(format!("{}/api/channels", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn list_channel_stats(&self, verbose: bool) -> Result<ChannelStatsResponse, Box<dyn Error>> {
        let mut req = self.http
            .get(format!("{}/api/channels/stats", self.base_url))
            .bearer_auth(&self.api_key);
        if verbose {
            req = req.query(&[("verbose", "1")]);
        }
        let resp = req.send().await?;
        Self::parse_response(resp).await
    }
    pub async fn get_agent_config(&self) -> Result<Value, Box<dyn Error>> {
        let resp = self.http
            .get(format!("{}/api/agents/me", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn update_agent_config(&self, config: &Value) -> Result<Value, Box<dyn Error>> {
        let resp = self.http
            .put(format!("{}/api/agents/me/config", self.base_url))
            .bearer_auth(&self.api_key)
            .json(config)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn register_session(&self, id: &str, branch: Option<&str>, cwd: Option<&str>, label: Option<&str>, status: Option<&str>, status_text: Option<&str>) -> Result<(), Box<dyn Error>> {
        let mut body = serde_json::json!({ "id": id });
        if let Some(b) = branch { body["branch"] = serde_json::Value::String(b.to_owned()); }
        if let Some(c) = cwd { body["cwd"] = serde_json::Value::String(c.to_owned()); }
        if let Some(l) = label { body["label"] = serde_json::Value::String(l.to_owned()); }
        if let Some(s) = status { body["status"] = serde_json::Value::String(s.to_owned()); }
        if let Some(t) = status_text { body["status_text"] = serde_json::Value::String(t.to_owned()); }
        let resp = self.http
            .post(format!("{}/api/sessions", self.base_url))
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(format!("session register failed ({status}): {text}").into());
        }
        Ok(())
    }
    pub async fn list_sessions(&self) -> Result<crate::types::SessionsResponse, Box<dyn Error>> {
        let resp = self.http
            .get(format!("{}/api/sessions?all=true", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn heartbeat_session(&self, id: &str, status: Option<&str>, status_text: Option<&str>) -> Result<(), Box<dyn Error>> {
        let mut req = self.http
            .patch(format!("{}/api/sessions/{}", self.base_url, id))
            .bearer_auth(&self.api_key);
        if status.is_some() || status_text.is_some() {
            let mut body = serde_json::Map::new();
            if let Some(s) = status { body.insert("status".into(), serde_json::Value::String(s.to_owned())); }
            if let Some(t) = status_text { body.insert("status_text".into(), serde_json::Value::String(t.to_owned())); }
            req = req.json(&body);
        }
        let resp = req.send().await?;
        if !resp.status().is_success() { /* ignore heartbeat failures */ }
        Ok(())
    }
    pub async fn mark_all_read(&self) -> Result<u32, Box<dyn Error>> {
        let resp = self.http
            .post(format!("{}/api/messages/mark-all-read", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        let data: Value = Self::parse_response(resp).await?;
        Ok(data["marked"].as_u64().unwrap_or(0) as u32)
    }
    pub async fn inbox_count(&self, priority: Option<&str>, session_id: Option<&str>) -> Result<u32, Box<dyn Error>> {
        let mut req = self.http
            .get(format!("{}/api/messages", self.base_url))
            .bearer_auth(&self.api_key)
            .query(&[("direction", "boss_to_agent"), ("unread", "true"), ("limit", "0")]);
        if let Some(p) = priority {
            req = req.query(&[("priority", p)]);
        }
        if let Some(sid) = session_id {
            req = req.query(&[("target_session", sid)]);
        }
        let resp = req.send().await?;
        let data: Value = Self::parse_response(resp).await?;
        Ok(data["total"].as_u64().unwrap_or(0) as u32)
    }
    pub async fn inbox_count_a2a(&self, session_id: Option<&str>) -> Result<u32, Box<dyn Error>> {
        let mut req = self.http
            .get(format!("{}/api/messages", self.base_url))
            .bearer_auth(&self.api_key)
            .query(&[("direction", "agent_to_agent"), ("unread", "true"), ("limit", "0")]);
        if let Some(sid) = session_id {
            req = req.query(&[("target_session", sid)]);
        }
        let resp = req.send().await?;
        let data: Value = Self::parse_response(resp).await?;
        Ok(data["total"].as_u64().unwrap_or(0) as u32)
    }
    pub async fn react(&self, id: &str, emoji: &str) -> Result<(), Box<dyn Error>> {
        let resp = self.http
            .post(format!("{}/api/messages/{}/react", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "emoji": emoji }))
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("react failed ({}): {}", status, body).into());
        }
        Ok(())
    }
    pub async fn get_reactions(&self, id: &str) -> Result<ReactionsResponse, Box<dyn Error>> {
        let resp = self.http
            .get(format!("{}/api/messages/{}/reactions", self.base_url, id))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn upload_file(&self, path: &str) -> Result<UploadResponse, Box<dyn Error>> {
        let file_path = std::path::Path::new(path);
        if !file_path.exists() {
            return Err(format!("file not found: {}", path).into());
        }
        let filename = file_path.file_name().unwrap_or_default().to_string_lossy().to_string();
        let data = std::fs::read(file_path)?;
        let mime = mime_from_ext(&filename);
        let part = reqwest::multipart::Part::bytes(data)
            .file_name(filename)
            .mime_str(&mime)?;
        let form = reqwest::multipart::Form::new().part("file", part);
        let resp = self.http
            .post(format!("{}/api/attachments/upload", self.base_url))
            .bearer_auth(&self.api_key)
            .multipart(form)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub(crate) async fn parse_response<T: serde::de::DeserializeOwned>(resp: reqwest::Response) -> Result<T, Box<dyn Error>> {
        if resp.status().is_success() {
            let parsed = resp.json::<T>().await?;
            Ok(parsed)
        } else {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            Err(format!("request failed ({}): {}", status, body).into())
        }
    }
}
mod bosses;
mod messages;
mod routing;
mod groups;
