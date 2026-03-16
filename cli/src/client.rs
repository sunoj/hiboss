// Purpose: Encapsulate HTTP calls to the hiboss server with auth and error handling.
// Exports: HiBossClient and its methods for messaging workflows.
// Dependencies: reqwest, serde_json, crate::types, std::error::Error.

use crate::types::{AgentsResponse, ChannelsResponse, CreateAgentResponse, Message, MessagesResponse, PollResponse, ReplyRequest, SendRequest, SendResponse, StatusUpdate};
use reqwest::Client;
use serde_json::Value;
use std::error::Error;

pub struct HiBossClient {
    base_url: String,
    api_key: String,
    http: Client,
}

impl HiBossClient {
    pub fn new(server: &str, key: &str) -> Self {
        let trimmed = server.trim_end_matches('/');
        Self {
            base_url: trimmed.to_owned(),
            api_key: key.to_owned(),
            http: Client::new(),
        }
    }

    pub async fn send_message(&self, req: &SendRequest) -> Result<SendResponse, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/messages", self.base_url))
            .bearer_auth(&self.api_key)
            .json(req)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn list_messages(&self, unread: bool, all: bool, limit: u32, priority: Option<&str>) -> Result<MessagesResponse, Box<dyn Error>> {
        let mut request = self
            .http
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
        let resp = request.send().await?;
        Self::parse_response(resp).await
    }

    pub async fn get_message(&self, id: &str) -> Result<Message, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/messages/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn reply_to(&self, id: &str, body: &str) -> Result<Message, Box<dyn Error>> {
        let req = ReplyRequest {
            body: body.to_owned(),
        };
        let resp = self
            .http
            .post(format!("{}/api/messages/{}/reply", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&req)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn update_status(&self, id: &str, status: &str) -> Result<Message, Box<dyn Error>> {
        let req = StatusUpdate {
            status: status.to_owned(),
        };
        let resp = self
            .http
            .patch(format!("{}/api/messages/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&req)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn poll_reply(&self, id: &str, timeout: u32) -> Result<PollResponse, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/messages/{}/poll", self.base_url, id))
            .bearer_auth(&self.api_key)
            .query(&[("timeout", timeout.to_string())])
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn create_agent(&self, name: &str) -> Result<CreateAgentResponse, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/keys", self.base_url))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "name": name }))
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn list_agents(&self) -> Result<AgentsResponse, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/keys", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn set_channel(&self, channel: &str, config: &Value) -> Result<Value, Box<dyn Error>> {
        let resp = self
            .http
            .put(format!("{}/api/channels/{}", self.base_url, channel))
            .bearer_auth(&self.api_key)
            .json(config)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn list_channels(&self) -> Result<ChannelsResponse, Box<dyn Error>> {
        let resp = self
            .http
            .get(format!("{}/api/channels", self.base_url))
            .bearer_auth(&self.api_key)
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    async fn parse_response<T: serde::de::DeserializeOwned>(resp: reqwest::Response) -> Result<T, Box<dyn Error>> {
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
