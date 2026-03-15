// Purpose: Define API-aligned data shapes for hiboss CLI requests and responses.
// Exports: Message, SendRequest, SendResponse, MessagesResponse, ReplyRequest, StatusUpdate, PollResponse.
// Dependencies: serde, serde_json, chrono, std::collections::HashMap.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub agent_id: Option<String>,
    pub direction: Option<String>,
    pub mode: Option<String>,
    pub channel: Option<String>,
    pub body: Option<String>,
    pub status: Option<String>,
    pub reply_to: Option<String>,
    pub priority: Option<String>,
    pub metadata: Option<HashMap<String, Value>>,
    pub created_at: Option<DateTime<Utc>>,
    pub updated_at: Option<DateTime<Utc>>,
    pub replies: Option<Vec<Message>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SendRequest {
    pub body: String,
    pub mode: String,
    pub priority: String,
    pub channel: Option<String>,
    pub metadata: Option<HashMap<String, Value>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SendResponse {
    pub id: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MessagesResponse {
    pub messages: Vec<Message>,
    pub total: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReplyRequest {
    pub body: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StatusUpdate {
    pub status: String,
}

pub type PollResponse = Message;
