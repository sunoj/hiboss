// Purpose: SSE client for real-time message streaming from hiboss server.
// Exports: SseEvent struct and connect_sse function.
// Dependencies: reqwest, tokio::sync::mpsc, futures_util::StreamExt.

use futures_util::StreamExt;
use reqwest::Client;
use std::error::Error;
use tokio::sync::mpsc;

pub struct SseEvent {
    pub event_type: String,
    pub data: String,
}

pub async fn connect_sse(
    client: &Client,
    url: &str,
    auth_token: &str,
    tx: mpsc::Sender<SseEvent>,
) -> Result<(), Box<dyn Error>> {
    let response = client
        .get(url)
        .header("Authorization", format!("Bearer {}", auth_token))
        .header("Accept", "text/event-stream")
        .send()
        .await?;
    if !response.status().is_success() {
        return Err(format!("SSE connect failed: {}", response.status()).into());
    }
    let mut stream = response.bytes_stream();
    let mut buffer = String::new();
    let mut current_event = String::from("message");
    let mut current_data = String::new();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        buffer.push_str(&String::from_utf8_lossy(&chunk));
        while let Some(pos) = buffer.find("\n\n") {
            let block = buffer[..pos].to_string();
            buffer = buffer[pos + 2..].to_string();
            for line in block.lines() {
                if let Some(val) = line.strip_prefix("event: ") {
                    current_event = val.to_string();
                } else if let Some(val) = line.strip_prefix("data: ") {
                    current_data = val.to_string();
                }
            }
            if !current_data.is_empty() {
                let _ = tx
                    .send(SseEvent {
                        event_type: current_event.clone(),
                        data: current_data.clone(),
                    })
                    .await;
                current_data.clear();
                current_event = "message".to_string();
            }
        }
    }
    Ok(())
}
