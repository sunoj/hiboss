// Session inventory and resolved peer target response shapes.
// Exports SessionInfo, SessionsResponse, SendTarget; depends on serde.
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct SendTarget {
    pub id: String,
    pub label: Option<String>,
    pub nickname: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SessionInfo {
    pub id: String,
    pub agent_id: String,
    pub agent_name: Option<String>,
    pub label: Option<String>,
    pub nickname: Option<String>,
    pub branch: Option<String>,
    pub cwd: Option<String>,
    pub status: Option<String>,
    pub status_text: Option<String>,
    pub started_at: Option<String>,
    pub last_seen_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SessionsResponse {
    pub sessions: Vec<SessionInfo>,
}
