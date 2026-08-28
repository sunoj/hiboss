// Purpose: Implement message-focused HiBossClient HTTP methods.
// Exports: extension impl for listing, reading, editing, and reacting to messages.
// Dependencies: super::HiBossClient, crate::types, reqwest, serde_json.

use super::HiBossClient;
use crate::types::{Message, MessagesResponse, PollResponse, ReplyRequest, SendResponse, StatusUpdate};
use reqwest::StatusCode;
use serde::Deserialize;
use std::error::Error;
use std::time::{Duration, Instant};

#[derive(Debug, Deserialize)]
struct TargetCandidate {
    label: Option<String>,
    id: String,
    idle_minutes: Option<u32>,
}

#[derive(Debug, Deserialize)]
struct TargetError {
    error: String,
    target: String,
    #[serde(default)]
    candidates: Vec<TargetCandidate>,
}

fn format_target_error(status: StatusCode, body: &str) -> Option<String> {
    if status != StatusCode::NOT_FOUND && status != StatusCode::CONFLICT {
        return None;
    }
    let error = serde_json::from_str::<TargetError>(body).ok()?;
    let candidates = error
        .candidates
        .iter()
        .map(|candidate| {
            let target = candidate.label.as_deref().unwrap_or(candidate.id.as_str());
            let idle = candidate
                .idle_minutes
                .map(|minutes| format!(", idle {minutes}m"))
                .unwrap_or_default();
            format!("{target} ({}{idle})", crate::helpers::short_id(&candidate.id))
        })
        .collect::<Vec<_>>();
    let message = match error.error.as_str() {
        "target_not_found" => match candidates.is_empty() {
            true => format!("target '{}' was not found; no active targets are available", error.target),
            false => format!("target '{}' was not found; valid targets: {}", error.target, candidates.join(", ")),
        },
        "ambiguous_target" => format!("target '{}' is ambiguous; choose one of: {}", error.target, candidates.join(", ")),
        _ => return None,
    };
    Some(message)
}

pub(crate) async fn parse_send_response(
    resp: reqwest::Response,
) -> Result<SendResponse, Box<dyn Error>> {
    if resp.status().is_success() {
        return Ok(resp.json::<SendResponse>().await?);
    }
    let status = resp.status();
    let req_id = resp
        .headers()
        .get("x-request-id")
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned);
    let body = resp.text().await.unwrap_or_default();
    let body = format_target_error(status, &body).unwrap_or(body);
    Err(super::format_http_error("request failed", status, req_id, body).into())
}

impl HiBossClient {
    pub async fn wait_for_delivery(
        &self,
        id: &str,
        timeout: Duration,
    ) -> Result<String, Box<dyn Error>> {
        let deadline = Instant::now() + timeout;
        loop {
            let message = self.get_message(id).await?;
            if message.status.as_deref() != Some("sent") {
                return Ok(message.status.unwrap_or_else(|| "unknown".to_owned()));
            }
            if Instant::now() >= deadline {
                return Err(format!("timed out waiting for message {id} to leave sent").into());
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    }

    pub async fn list_messages(
        &self,
        unread: bool,
        all: bool,
        limit: u32,
        priority: Option<&str>,
        msg_type: Option<&str>,
        session: Option<&str>,
        from: Option<&str>,
        direction: Option<&str>,
        target_session: Option<&str>,
        search: Option<&str>,
        status: Option<&str>,
    ) -> Result<MessagesResponse, Box<dyn Error>> {
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
        if let Some(s) = status {
            request = request.query(&[("status", s)]);
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

    pub async fn edit_message_body(&self, id: &str, body: &str) -> Result<Message, Box<dyn Error>> {
        let resp = self
            .http
            .patch(format!("{}/api/messages/{}", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "body": body }))
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn forward_message(
        &self,
        id: &str,
        channel: &str,
    ) -> Result<Message, Box<dyn Error>> {
        let resp = self
            .http
            .post(format!("{}/api/messages/{}/forward", self.base_url, id))
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "channel": channel }))
            .send()
            .await?;
        Self::parse_response(resp).await
    }

    pub async fn poll_reply(&self, id: &str, timeout: u32) -> Result<PollResponse, Box<dyn Error>> {
        let poll_timeout = u64::from(timeout).saturating_add(30).max(120);
        let resp = self
            .poll_http
            .post(format!("{}/api/messages/{}/poll", self.base_url, id))
            .bearer_auth(&self.api_key)
            .query(&[("timeout", timeout.to_string())])
            .timeout(Duration::from_secs(poll_timeout))
            .send()
            .await?;
        Self::parse_response(resp).await
    }
}

#[cfg(test)]
mod tests {
    use super::format_target_error;
    use reqwest::StatusCode;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    #[test]
    fn target_not_found_lists_valid_targets() {
        let message = format_target_error(
            StatusCode::NOT_FOUND,
            r#"{"error":"target_not_found","target":"smart-router","candidates":[{"label":"smart-router/main","id":"aefb4ffd12345678"}]}"#,
        )
        .expect("target error formats");
        assert_eq!(
            message,
            "target 'smart-router' was not found; valid targets: smart-router/main (aefb4ffd)"
        );
    }

    #[test]
    fn target_not_found_formats_stale_target_idle_time() {
        let message = format_target_error(
            StatusCode::NOT_FOUND,
            r#"{"error":"target_not_found","target":"missing","candidates":[{"label":"peer/main","id":"peer123456789","idle_minutes":20}],"remaining":0}"#,
        )
        .expect("target error formats");
        assert_eq!(
            message,
            "target 'missing' was not found; valid targets: peer/main (peer1234, idle 20m)"
        );
    }

    #[test]
    fn ambiguous_target_lists_choices() {
        let message = format_target_error(
            StatusCode::CONFLICT,
            r#"{"error":"ambiguous_target","target":"router","candidates":[{"label":"router/main","id":"one123456789"},{"label":"router/dev","id":"two123456789"}]}"#,
        )
        .expect("target error formats");
        assert_eq!(
            message,
            "target 'router' is ambiguous; choose one of: router/main (one12345), router/dev (two12345)"
        );
    }

    #[test]
    fn unrelated_status_keeps_target_body_unformatted() {
        assert!(format_target_error(StatusCode::BAD_REQUEST, "{} ").is_none());
    }

    #[tokio::test]
    async fn wait_for_delivery_returns_after_queue_is_left() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind test server");
        let address = listener.local_addr().expect("read test address");
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept test request");
            let mut request = [0_u8; 512];
            let _ = stream.read(&mut request);
            let body = r#"{"id":"message","status":"delivered"}"#;
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                body.len(), body
            );
            stream.write_all(response.as_bytes()).expect("write test response");
        });
        let client = super::HiBossClient::new(&format!("http://{address}"), "test-key");
        let status = client
            .wait_for_delivery("message", std::time::Duration::ZERO)
            .await
            .expect("delivery state");
        assert_eq!(status, "delivered");
    }
}
