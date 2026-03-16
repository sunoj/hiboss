// Purpose: Define API-aligned data shapes for hiboss CLI requests and responses.
// Exports: Message, SendRequest, SendResponse, MessagesResponse, ReplyRequest, StatusUpdate, PollResponse.
// Dependencies: serde, serde_json, std::collections::HashMap.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub agent_id: Option<String>,
    pub agent_name: Option<String>,
    pub direction: Option<String>,
    pub mode: Option<String>,
    pub channel: Option<String>,
    pub body: Option<String>,
    pub status: Option<String>,
    pub reply_to: Option<String>,
    pub priority: Option<String>,
    pub metadata: Option<HashMap<String, Value>>,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub replies: Option<Vec<Message>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SendRequest {
    pub body: String,
    pub mode: String,
    pub priority: String,
    pub channel: Option<String>,
    pub metadata: Option<HashMap<String, Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_url: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SendResponse {
    pub id: String,
    pub status: String,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MessagesResponse {
    pub messages: Vec<Message>,
    pub total: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateAgentResponse {
    pub id: String,
    pub name: String,
    pub key: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AgentInfo {
    pub id: String,
    pub name: String,
    pub status: Option<String>,
    pub created_at: Option<String>,
    pub last_used_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AgentsResponse {
    pub agents: Vec<AgentInfo>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ChannelInfo {
    pub id: String,
    pub channel: String,
    pub config: Value,
    pub enabled: bool,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ChannelsResponse {
    pub channels: Vec<ChannelInfo>,
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
