// Purpose: Define HiBossClient plus messaging, admin, and upload helpers.
// Exports: HiBossClient struct, core messaging + admin methods, upload and helpers.
// Dependencies: reqwest, serde_json, thiserror, crate::types, std::error::Error.
use crate::types::{
    AgentsResponse, ChannelStatsResponse, ChannelsResponse, CreateAgentResponse, ReactionsResponse,
    UploadResponse,
};
use reqwest::{Client, Method};
use serde_json::Value;
use std::error::Error;
use std::time::Duration;
mod discord_registration;
pub(crate) fn mime_from_ext(filename: &str) -> String {
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

/// A non-success HTTP response, kept typed so callers can match the exact server rejection.
#[derive(Debug, thiserror::Error)]
#[error(
    "{prefix} ({status}): {body}{}",
    .request_id.as_deref().filter(|id| !id.is_empty())
        .map(|id| format!(" [req-id={id}]")).unwrap_or_default()
)]
pub struct HttpError {
    pub prefix: &'static str,
    pub status: reqwest::StatusCode,
    pub request_id: Option<String>,
    pub body: String,
}

fn http_error(
    prefix: &'static str,
    status: reqwest::StatusCode,
    request_id: Option<String>,
    body: String,
) -> HttpError {
    HttpError { prefix, status, request_id, body }
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
    fn request(&self, method: Method, path: &str) -> reqwest::RequestBuilder {
        self.http
            .request(method, format!("{}{path}", self.base_url))
            .bearer_auth(&self.api_key)
    }
    pub async fn create_agent(&self, name: &str) -> Result<CreateAgentResponse, Box<dyn Error>> {
        Self::send_json(
            self.request(Method::POST, "/api/keys")
                .json(&serde_json::json!({ "name": name }))
        ).await
    }
    pub async fn list_agents(&self) -> Result<AgentsResponse, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, "/api/agents")).await
    }
    pub async fn set_channel(
        &self,
        channel: &str,
        config: &Value,
    ) -> Result<Value, Box<dyn Error>> {
        Self::send_json(
            self.request(Method::PUT, &format!("/api/channels/{}", channel))
                .json(config)
        ).await
    }
    pub async fn list_channels(&self) -> Result<ChannelsResponse, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, "/api/channels")).await
    }
    pub async fn list_channel_stats(
        &self,
        verbose: bool,
    ) -> Result<ChannelStatsResponse, Box<dyn Error>> {
        let mut req = self.request(Method::GET, "/api/channels/stats");
        if verbose {
            req = req.query(&[("verbose", "1")]);
        }
        Self::send_json(req).await
    }
    pub async fn get_agent_config(&self) -> Result<Value, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, "/api/agents/me")).await
    }
    pub async fn update_agent_config(&self, config: &Value) -> Result<Value, Box<dyn Error>> {
        Self::send_json(
            self.request(Method::PUT, "/api/agents/me/config")
                .json(config)
        ).await
    }
    pub async fn inbox_count(
        &self,
        priority: Option<&str>,
        session_id: Option<&str>,
    ) -> Result<u32, Box<dyn Error>> {
        let mut req = self.request(Method::GET, "/api/messages")
            .query(&[
                ("direction", "boss_to_agent"),
                ("unread", "true"),
                ("limit", "0"),
            ]);
        if let Some(p) = priority {
            req = req.query(&[("priority", p)]);
        }
        if let Some(sid) = session_id {
            req = req.query(&[("target_session", sid)]);
        }
        let data: Value = Self::send_json(req).await?;
        Ok(data["total"].as_u64().unwrap_or(0) as u32)
    }
    pub async fn inbox_count_a2a(&self, session_id: Option<&str>) -> Result<u32, Box<dyn Error>> {
        let mut req = self.request(Method::GET, "/api/messages")
            .query(&[
                ("direction", "agent_to_agent"),
                ("unread", "true"),
                ("limit", "0"),
            ]);
        if let Some(sid) = session_id {
            req = req.query(&[("target_session", sid)]);
        }
        let data: Value = Self::send_json(req).await?;
        Ok(data["total"].as_u64().unwrap_or(0) as u32)
    }
    pub async fn react(&self, id: &str, emoji: &str) -> Result<(), Box<dyn Error>> {
        let resp = self.request(Method::POST, &format!("/api/messages/{}/react", id))
            .json(&serde_json::json!({ "emoji": emoji }))
            .send()
            .await?;
        if !resp.status().is_success() {
            let status = resp.status();
            let req_id = resp
                .headers()
                .get("x-request-id")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string());
            let body = resp.text().await.unwrap_or_default();
            return Err(http_error("react failed", status, req_id, body).into());
        }
        Ok(())
    }
    pub async fn get_reactions(&self, id: &str) -> Result<ReactionsResponse, Box<dyn Error>> {
        Self::send_json(self.request(Method::GET, &format!("/api/messages/{}/reactions", id))).await
    }
    pub async fn upload_file(&self, path: &str) -> Result<UploadResponse, Box<dyn Error>> {
        let file_path = std::path::Path::new(path);
        if !file_path.exists() {
            return Err(format!("file not found: {}", path).into());
        }
        let filename = file_path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let data = std::fs::read(file_path)?;
        let mime = mime_from_ext(&filename);
        let part = reqwest::multipart::Part::bytes(data)
            .file_name(filename)
            .mime_str(&mime)?;
        let form = reqwest::multipart::Form::new().part("file", part);
        Self::send_json(
            self.request(Method::POST, "/api/attachments/upload")
                .multipart(form)
        ).await
    }
    async fn delete(&self, path: &str, error_prefix: &str) -> Result<(), Box<dyn Error>> {
        Self::empty_response(self.request(Method::DELETE, path).send().await?, error_prefix).await
    }
    async fn empty_response(resp: reqwest::Response, error_prefix: &str) -> Result<(), Box<dyn Error>> {
        if resp.status().is_success() {
            Ok(())
        } else {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            Err(format!("{} ({}): {}", error_prefix, status, body).into())
        }
    }
    async fn send_json<T: serde::de::DeserializeOwned>(
        request: reqwest::RequestBuilder,
    ) -> Result<T, Box<dyn Error>> {
        Self::parse_response(request.send().await?).await
    }
    pub(crate) async fn parse_response<T: serde::de::DeserializeOwned>(
        resp: reqwest::Response,
    ) -> Result<T, Box<dyn Error>> {
        if resp.status().is_success() {
            let parsed = resp.json::<T>().await?;
            Ok(parsed)
        } else {
            let status = resp.status();
            let req_id = resp
                .headers()
                .get("x-request-id")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string());
            let body = resp.text().await.unwrap_or_default();
            Err(http_error("request failed", status, req_id, body).into())
        }
    }
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
mod sessions;
mod bosses;
mod groups;
mod messages;
mod signed;
mod panels;
mod progress;
pub(crate) mod box_items;
mod projects;
mod routing;

pub use panels::{PanelConnectionTicket, PanelPublishResponse};
