// Purpose: Test message-client error formatting and delivery waiting.
// Covers target lookup diagnostics and queued-message status transitions.
// Dependencies: parent message client module and a local TCP fixture.

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
