// Purpose: Define API-aligned data shapes for hiboss CLI requests and responses.
// Exports: Message, SendRequest, SendTarget, SendResponse, MessagesResponse, ReplyRequest, StatusUpdate, PollResponse.
// Dependencies: serde, serde_json, std::collections::HashMap.

use crate::team::ProgressTeam;
use serde::{Deserialize, Serialize};
use std::str::FromStr;
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
    #[serde(rename = "type")]
    pub message_type: Option<String>,
    pub metadata: Option<HashMap<String, Value>>,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub session_label: Option<String>,
    #[serde(default)]
    pub session_branch: Option<String>,
    #[serde(default)]
    pub session_status: Option<String>,
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
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    pub message_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SendTarget { pub id: String, #[serde(default)] pub label: Option<String> }

#[derive(Debug, Serialize, Deserialize)]
pub struct SendResponse {
    pub id: String,
    pub status: String,
    pub created_at: String,
    pub warning: Option<String>,
    #[serde(default)] pub target: Option<SendTarget>,
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
    pub role: Option<String>,
    pub session_info: Option<HashMap<String, Value>>,
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
pub struct ChannelStats {
    pub channel: String,
    pub total_sent: u32,
    pub total_delivered: u32,
    pub total_failed: u32,
    pub last_delivery_at: Option<String>,
    pub last_error: Option<String>,
    pub last_error_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DeliveryErrorInfo {
    pub channel: String,
    #[serde(default)]
    pub message_id: Option<String>,
    pub last_error: Option<String>,
    pub last_error_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DeliveryQueueStatus {
    pub total: u32,
    #[serde(default)]
    pub by_status: Vec<QueueStatusCount>,
    #[serde(default)]
    pub oldest_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct QueueStatusCount {
    pub status: String,
    pub total: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DirectionCount {
    pub channel: String,
    pub direction: String,
    pub total: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ChannelStatsResponse {
    pub channels: Vec<ChannelStats>,
    #[serde(default)]
    pub recent_errors: Vec<DeliveryErrorInfo>,
    #[serde(default)]
    pub delivery_queue: Option<DeliveryQueueStatus>,
    #[serde(default)]
    pub direction_counts: Vec<DirectionCount>,
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

#[derive(Debug, Serialize, Deserialize)]
pub struct SessionInfo {
    pub id: String,
    pub agent_id: String,
    #[serde(default)]
    pub agent_name: Option<String>,
    pub label: Option<String>,
    pub branch: Option<String>,
    pub cwd: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub status_text: Option<String>,
    pub started_at: Option<String>,
    pub last_seen_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SessionsResponse {
    pub sessions: Vec<SessionInfo>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Reaction {
    pub emoji: String,
    #[serde(default)]
    pub user: Option<String>,
    #[serde(default)]
    pub count: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReactionsResponse {
    pub reactions: Vec<Reaction>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UploadResponse {
    pub key: String,
    pub url: String,
    pub filename: String,
    pub content_type: String,
    pub size: u64,
}

/// A single media attachment on a progress post.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgressMediaItem {
    pub url: String,
    /// "image" or "video"
    pub kind: String,
    pub content_type: String,
    pub size: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub poster_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub alt: Option<String>,
}

/// Request body for POST /api/progress.
#[derive(Debug, Serialize, Deserialize)]
pub struct ProgressPostRequest {
    pub body: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub project: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub media: Option<Vec<ProgressMediaItem>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent_label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
}

/// A single progress post as returned by the server.
#[derive(Debug, Serialize, Deserialize)]
pub struct ProgressPost {
    pub id: String,
    pub project: String,
    pub agent_id: String,
    pub agent_name: Option<String>,
    pub session_id: Option<String>,
    pub body: String,
    #[serde(default)]
    pub media: Vec<ProgressMediaItem>,
    #[serde(default)]
    pub tags: Vec<String>,
    pub created_at: String,
    /// Team identity for this post. None only for posts from pre-v2 server versions.
    #[serde(default)]
    pub team: Option<ProgressTeam>,
    #[serde(default)]
    pub agent_label: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
}

/// Response from GET /api/progress.
#[derive(Debug, Serialize, Deserialize)]
pub struct ProgressFeedResponse {
    pub posts: Vec<ProgressPost>,
    pub next_cursor: Option<ProgressCursor>,
}

/// Composite keyset cursor for GET /api/progress.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProgressCursor {
    pub created_at: String,
    pub id: String,
}

impl FromStr for ProgressCursor {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        serde_json::from_str(value).map_err(|_| "before must be JSON with created_at and id".to_owned())
    }
}
