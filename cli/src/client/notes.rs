// Session note transport and response types.
// Exports typed note listing and read acknowledgement on HiBossClient.
use super::HiBossClient;
use serde::{Deserialize, Serialize};
use std::error::Error;

#[derive(Debug, Deserialize, Serialize)]
pub struct NoteImage {
    pub index: u32,
    pub content_type: String,
    pub bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
}
#[derive(Debug, Deserialize, Serialize)]
pub struct Note {
    pub id: String,
    pub session_id: String,
    pub agent_id: String,
    pub boss_name: String,
    pub body: String,
    pub status: String,
    pub created_at: String,
    pub read_at: Option<String>,
    #[serde(default)]
    pub images: Vec<NoteImage>,
}
#[derive(Debug, Deserialize, Serialize)]
pub struct NotesResponse {
    pub notes: Vec<Note>,
}
#[derive(Deserialize)]
struct ReadResponse {
    read: u32,
}
impl HiBossClient {
    pub async fn session_notes(
        &self,
        session: &str,
        all: bool,
    ) -> Result<NotesResponse, Box<dyn Error>> {
        let status = if all { "all" } else { "pending" };
        let path = format!(
            "/api/sessions/{}/notes?status={status}",
            session_segment(session)?
        );
        Self::send_json(self.request(reqwest::Method::GET, &path)).await
    }

    pub async fn note_image(
        &self,
        session: &str,
        note: &str,
        index: u32,
    ) -> Result<reqwest::Response, Box<dyn Error>> {
        let path = format!(
            "/api/sessions/{}/notes/{}/images/{index}",
            session_segment(session)?,
            session_segment(note)?
        );
        Self::checked_response(
            self.request(reqwest::Method::GET, &path).send().await?,
            "note image download failed",
        )
        .await
    }

    pub async fn read_notes(&self, session: &str, ids: &[&str]) -> Result<u32, Box<dyn Error>> {
        let path = format!("/api/sessions/{}/notes/read", session_segment(session)?);
        let response: ReadResponse = Self::send_json(
            self.request(reqwest::Method::POST, &path)
                .json(&serde_json::json!({ "ids": ids })),
        )
        .await?;
        Ok(response.read)
    }
}

fn session_segment(session: &str) -> Result<String, Box<dyn Error>> {
    let mut url = reqwest::Url::parse("http://localhost/")?;
    if let Ok(mut segments) = url.path_segments_mut() {
        segments.clear().push(session);
    }
    Ok(url.path().trim_start_matches('/').to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_ids_cannot_change_the_route_or_query() {
        assert_eq!(
            session_segment("a/b?c#d").expect("segment"),
            "a%2Fb%3Fc%23d"
        );
    }

    #[test]
    fn note_json_preserves_full_body_and_nullable_read_time() {
        let response: NotesResponse = serde_json::from_value(serde_json::json!({"notes": [{
            "id": "n", "session_id": "s", "agent_id": "a", "boss_name": "Boss",
            "body": "first\nsecond", "status": "pending", "created_at": "2026-11-02 10:00:00",
            "read_at": null
        }]}))
        .expect("contract response");
        assert_eq!(response.notes[0].body, "first\nsecond");
        assert!(response.notes[0].read_at.is_none());
    }
}
