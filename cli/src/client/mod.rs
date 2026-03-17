// Purpose: Define HiBossClient plus messaging, admin, and upload helpers.
// Exports: HiBossClient struct, core messaging + admin methods, upload and helpers.
// Dependencies: reqwest, serde_json, crate::types, std::error::Error.
use crate::types::{AgentsResponse, ChannelsResponse, CreateAgentResponse, Message, MessagesResponse, PollResponse, ReactionsResponse, ReplyRequest, SendRequest, SendResponse, StatusUpdate, UploadResponse};
use reqwest::Client;
use serde_json::Value;
use std::error::Error;
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
}
impl HiBossClient {
    pub fn new(server: &str, key: &str) -> Self {
        let trimmed = server.trim_end_matches('/');
        Self { base_url: trimmed.to_owned(), api_key: key.to_owned(), http: Client::new() }
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
    pub async fn list_messages(&self, unread: bool, all: bool, limit: u32, priority: Option<&str>, msg_type: Option<&str>, session: Option<&str>, from: Option<&str>) -> Result<MessagesResponse, Box<dyn Error>> {
        let mut request = self.http
            .get(format!("{}/api/messages", self.base_url))
            .bearer_auth(&self.api_key)
            .query(&[("limit", limit.to_string())]);
        if unread {
            request = request.query(&[("unread", "true")]);
        }
        if all {
            request = request.query(&[("offset", "0")]);
        }
        if let Some(p) = priority {
            request = request.query(&[("priority", p)]);
        }
        if let Some(t) = msg_type {
            request = request.query(&[("type", t)]);
        }
        if let Some(s) = session {
            request = request.query(&[("session", s)]);
        }
        if let Some(f) = from {
            request = request.query(&[("from", f)]);
        }
        let resp = request.send().await?;
        Self::parse_response(resp).await
    }
    pub async fn get_message(&self, id: &str) -> Result<Message, Box<dyn Error>> {
        let resp = self.http
            .get(format!("{}/api/messages/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn reply_to(&self, id: &str, body: &str) -> Result<Message, Box<dyn Error>> {
        let req = ReplyRequest { body: body.to_owned() };
        let resp = self.http
            .post(format!("{}/api/messages/{}/reply", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&req)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn update_status(&self, id: &str, status: &str) -> Result<Message, Box<dyn Error>> {
        let req = StatusUpdate { status: status.to_owned() };
        let resp = self.http
            .patch(format!("{}/api/messages/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&req)
            .send()
            .await?;
        Self::parse_response(resp).await
    }
    pub async fn poll_reply(&self, id: &str, timeout: u32) -> Result<PollResponse, Box<dyn Error>> {
        let resp = self.http
            .post(format!("{}/api/messages/{}/poll", self.base_url, id))
            .bearer_auth(&self.api_key)
            .query(&[("timeout", timeout.to_string())])
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
mod routing;
mod groups;
