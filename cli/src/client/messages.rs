// Purpose: Implement message-focused HiBossClient HTTP methods.
// Exports: extension impl for listing, reading, editing, and reacting to messages.
// Dependencies: super::HiBossClient, crate::types, reqwest, serde_json.

use super::HiBossClient;
use crate::types::{Message, MessagesResponse, PollResponse, ReplyRequest, StatusUpdate};
use std::error::Error;
use std::time::Duration;

impl HiBossClient {
    pub async fn list_messages(&self, unread: bool, all: bool, limit: u32, priority: Option<&str>, msg_type: Option<&str>, session: Option<&str>, from: Option<&str>, direction: Option<&str>, target_session: Option<&str>, search: Option<&str>) -> Result<MessagesResponse, Box<dyn Error>> {
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
        if let Some(d) = direction {
            request = request.query(&[("direction", d)]);
        }
        if let Some(ts) = target_session {
            request = request.query(&[("target_session", ts)]);
        }
        if let Some(s) = search {
            request = request.query(&[("search", s)]);
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

    pub async fn edit_message_body(&self, id: &str, body: &str) -> Result<Message, Box<dyn Error>> {
        let resp = self.http
            .patch(format!("{}/api/messages/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "body": body }))
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn forward_message(&self, id: &str, channel: &str) -> Result<Message, Box<dyn Error>> {
        let resp = self.http
            .post(format!("{}/api/messages/{}/forward", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "channel": channel }))
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn poll_reply(&self, id: &str, timeout: u32) -> Result<PollResponse, Box<dyn Error>> {
        let poll_timeout = u64::from(timeout).saturating_add(30).max(120);
        let resp = self.poll_http
            .post(format!("{}/api/messages/{}/poll", self.base_url, id))
            .bearer_auth(&self.api_key)
            .query(&[("timeout", timeout.to_string())])
            .timeout(Duration::from_secs(poll_timeout))
            .send()
            .await?;
        Self::parse_response(resp).await
    }
}
