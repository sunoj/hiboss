// Send a note reply through the ordinary signed message client and session repair path.
// Reuses send title/content validation and prints the server's message receipt.
use crate::{client::HiBossClient, session, types::SendRequest};
use std::{error::Error, path::Path};

pub(super) async fn run(
    client: &HiBossClient,
    session_id: &str,
    note_id: &str,
    text: &str,
    content_file: Option<&Path>,
) -> Result<(), Box<dyn Error>> {
    let body = super::super::message_text::title(text, false)?;
    let content = super::super::message_text::content(None, content_file)?;
    let metadata = super::super::message_text::metadata_fields([
        ("note_id", Some(serde_json::json!(note_id))),
        (
            "content",
            content
                .filter(|text| !text.is_empty())
                .map(serde_json::Value::String),
        ),
    ]);
    let mut request = SendRequest {
        body,
        mode: "async".to_owned(),
        timeout: None,
        priority: "normal".to_owned(),
        channel: None,
        metadata: Some(metadata),
        options: None,
        file_url: None,
        message_type: None,
        session_id: Some(session_id.to_owned()),
        to: None,
    };
    let receipt =
        super::super::session_register::send_with_session_heal(client, &mut request).await?;
    session::mark_replied();
    println!("{}", receipt.id);
    Ok(())
}
