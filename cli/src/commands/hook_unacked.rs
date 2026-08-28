// Purpose: Find and format outbound peer messages awaiting acknowledgement.
// Exports: unacknowledged_outbound_warning().
// Dependencies: crate::client, crate::types, time.

use crate::{client::HiBossClient, types::Message};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

pub(crate) async fn unacknowledged_outbound_warning(
    client: &HiBossClient,
    session_id: &str,
) -> Option<String> {
    let response = client
        .list_messages(
            false,
            false,
            100,
            None,
            None,
            Some(session_id),
            None,
            Some("agent_to_agent"),
            None,
            None,
            Some("sent"),
        )
        .await
        .ok()?;
    format_unacknowledged_warning(&response.messages, session_id, OffsetDateTime::now_utc())
}

fn format_unacknowledged_warning(
    messages: &[Message],
    session_id: &str,
    now: OffsetDateTime,
) -> Option<String> {
    let pending: Vec<&Message> = messages
        .iter()
        .filter(|message| {
            message.direction.as_deref() == Some("agent_to_agent")
                && message.status.as_deref() == Some("sent")
                && message.session_id.as_deref() == Some(session_id)
        })
        .collect();
    if pending.is_empty() {
        return None;
    }
    let oldest = pending
        .iter()
        .filter_map(|message| message.created_at.as_deref().and_then(parse_created_at))
        .min();
    let age = oldest
        .map(|created| format_age((now - created).whole_seconds()))
        .unwrap_or_else(|| "unknown".to_owned());
    let ids = pending
        .iter()
        .map(|message| message.id.as_str())
        .collect::<Vec<_>>()
        .join(", ");
    Some(format!(
        "UNACKED WARNING: {} outbound peer message(s) are still unacknowledged (oldest {age}) — they may not have been read. Message IDs: {ids}. Check delivery with: hiboss status <id>",
        pending.len()
    ))
}

fn parse_created_at(value: &str) -> Option<OffsetDateTime> {
    OffsetDateTime::parse(value, &Rfc3339).ok().or_else(|| {
        let (date, clock) = value.split_once(' ')?;
        OffsetDateTime::parse(&format!("{date}T{clock}Z"), &Rfc3339).ok()
    })
}

fn format_age(seconds: i64) -> String {
    let minutes = seconds.max(0) / 60;
    if minutes < 60 {
        return format!("{minutes}m");
    }
    format!("{}h {}m", minutes / 60, minutes % 60)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    fn message(id: &str, status: &str, session_id: &str, created_at: &str) -> Message {
        Message {
            id: id.to_owned(),
            agent_id: None,
            agent_name: None,
            direction: Some("agent_to_agent".to_owned()),
            mode: None,
            channel: None,
            body: None,
            status: Some(status.to_owned()),
            reply_to: None,
            priority: None,
            message_type: None,
            metadata: None,
            created_at: Some(created_at.to_owned()),
            updated_at: None,
            session_id: Some(session_id.to_owned()),
            session_label: None,
            session_branch: None,
            session_status: None,
            replies: None,
        }
    }

    #[test]
    fn formats_sent_ids_and_oldest_age() {
        let messages = vec![
            message("new-id", "sent", "session-1", "2026-08-28T00:14:00Z"),
            message("old-id", "sent", "session-1", "2026-08-28 00:00:00"),
            message("delivered-id", "delivered", "session-1", "2026-08-28T00:01:00Z"),
        ];
        let now = OffsetDateTime::parse("2026-08-28T00:24:00Z", &Rfc3339)
            .expect("test timestamp");
        let warning = format_unacknowledged_warning(&messages, "session-1", now)
            .expect("warning");
        assert!(warning.contains("UNACKED WARNING: 2 outbound peer message(s)"));
        assert!(warning.contains("oldest 24m"));
        assert!(warning.contains("old-id") && warning.contains("new-id"));
        assert!(warning.contains("hiboss status <id>"));
    }

    #[test]
    fn ignores_other_sessions_and_acknowledged_messages() {
        let messages = vec![
            message("other-session", "sent", "session-2", "2026-08-28T00:00:00Z"),
            message("already-delivered", "delivered", "session-1", "2026-08-28T00:00:00Z"),
        ];
        let now = OffsetDateTime::parse("2026-08-28T00:24:00Z", &Rfc3339)
            .expect("test timestamp");
        assert!(format_unacknowledged_warning(&messages, "session-1", now).is_none());
    }

    #[tokio::test]
    async fn queries_sent_outbound_messages_for_the_current_session() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind test server");
        let address = listener.local_addr().expect("read test address");
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept test request");
            let mut request = [0_u8; 4096];
            let bytes = stream.read(&mut request).expect("read test request");
            let request = String::from_utf8_lossy(&request[..bytes]);
            assert!(request.contains("direction=agent_to_agent"));
            assert!(request.contains("session=session-1"));
            assert!(request.contains("status=sent"));
            let body = r#"{"messages":[{"id":"sent-id","direction":"agent_to_agent","status":"sent","session_id":"session-1","created_at":"2026-08-28T00:00:00Z"}],"total":1}"#;
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                body.len(), body
            );
            stream.write_all(response.as_bytes()).expect("write test response");
        });
        let client = HiBossClient::new(&format!("http://{address}"), "test-key");
        let warning = unacknowledged_outbound_warning(&client, "session-1")
            .await
            .expect("warning");
        assert!(warning.contains("sent-id"));
    }
}
