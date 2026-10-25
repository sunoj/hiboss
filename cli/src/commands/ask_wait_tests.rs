// Exercises short internal deadlines without weakening the public CLI timeout range.
// Covers final reads, dropped response bodies, and permanent malformed JSON.
// Dependencies: real loopback TCP, Tokio, HiBossClient, and ask result formatting.

use super::wait_for_reply;
use crate::client::HiBossClient;
use crate::commands::ask::ChoicePayload;
use crate::commands::ask_result::AskResult;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::{JoinHandle, JoinSet};
use tokio::time::Instant;

#[derive(Clone, Copy)]
enum Scenario {
    Empty,
    Stalled,
    InsidePoll,
    FinalReadTransient,
    FinalReadUnavailable,
    FinalReadUnauthorized,
    Backoff,
    DroppedBody,
    MalformedJson,
    SelfReplyOnly,
    PollSelfReply,
}

struct Server {
    client: HiBossClient,
    paths: Arc<Mutex<Vec<String>>>,
    worker: JoinHandle<()>,
}

impl Server {
    async fn start(scenario: Scenario) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").await.expect("listen");
        let client = HiBossClient::new(
            &format!("http://{}", listener.local_addr().expect("address")),
            "synthetic-wait-key",
        );
        let paths = Arc::new(Mutex::new(Vec::new()));
        let log = paths.clone();
        let stored = Arc::new(AtomicBool::new(false));
        let worker = tokio::spawn(async move {
            let mut requests = JoinSet::new();
            let reply = stored.clone();
            requests.spawn(async move {
                let millis = if matches!(
                    scenario,
                    Scenario::InsidePoll | Scenario::FinalReadTransient
                ) {
                    500
                } else {
                    1600
                };
                tokio::time::sleep(Duration::from_millis(millis)).await;
                reply.store(true, Ordering::SeqCst);
            });
            while let Ok((stream, _)) = listener.accept().await {
                requests.spawn(answer(stream, scenario, stored.clone(), log.clone()));
            }
        });
        Self {
            client,
            paths,
            worker,
        }
    }

    fn paths(&self) -> Vec<String> {
        self.paths.lock().expect("paths").clone()
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        self.worker.abort();
    }
}

async fn answer(
    mut stream: TcpStream,
    scenario: Scenario,
    stored: Arc<AtomicBool>,
    paths: Arc<Mutex<Vec<String>>>,
) {
    let mut bytes = Vec::new();
    let mut chunk = [0; 1024];
    while !bytes.windows(4).any(|part| part == b"\r\n\r\n") {
        let size = stream.read(&mut chunk).await.expect("request");
        if size == 0 {
            return;
        }
        bytes.extend_from_slice(&chunk[..size]);
    }
    let text = String::from_utf8_lossy(&bytes);
    let path = text.split_whitespace().nth(1).expect("path").to_owned();
    let poll = path.contains("/poll?");
    let index = {
        let mut log = paths.lock().expect("paths");
        let index = log.len();
        log.push(path);
        index
    };
    if poll
        && matches!(
            scenario,
            Scenario::Stalled
                | Scenario::InsidePoll
                | Scenario::FinalReadTransient
                | Scenario::FinalReadUnavailable
                | Scenario::FinalReadUnauthorized
        )
    {
        tokio::time::sleep(Duration::from_secs(3)).await;
    }
    let has_reply = match scenario {
        Scenario::InsidePoll | Scenario::Backoff | Scenario::FinalReadTransient => {
            stored.load(Ordering::SeqCst)
        }
        Scenario::DroppedBody => index > 0,
        _ => false,
    };
    send_body(&mut stream, scenario, has_reply, index).await;
}

/// The thread read of an unanswered ask: only the asker's own follow-up is a child.
const SELF_REPLY_BODY: &str = r#"{"id":"ask-1","agent_id":"agent-a","direction":"agent_to_boss","replies":[{"id":"own-1","agent_id":"agent-a","direction":"agent_to_boss","body":"Yes"}]}"#;

async fn send_body(stream: &mut TcpStream, scenario: Scenario, has_reply: bool, index: usize) {
    if index > 0
        && matches!(
            scenario,
            Scenario::FinalReadUnavailable | Scenario::FinalReadUnauthorized
        )
    {
        let status = if matches!(scenario, Scenario::FinalReadUnavailable) {
            503
        } else {
            401
        };
        let wire =
            format!("HTTP/1.1 {status} Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        stream
            .write_all(wire.as_bytes())
            .await
            .expect("error response");
        return;
    }
    if matches!(scenario, Scenario::FinalReadTransient) && index == 1 {
        assert!(has_reply, "reply stored at 500ms");
        stream
            .write_all(
                b"HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            )
            .await
            .expect("503 response");
        return;
    }
    let body = if matches!(scenario, Scenario::MalformedJson) {
        "{broken"
    } else if (matches!(scenario, Scenario::SelfReplyOnly) && index > 0)
        || (matches!(scenario, Scenario::PollSelfReply) && index == 0)
    {
        SELF_REPLY_BODY
    } else if has_reply {
        r#"{"id":"ask-1","direction":"agent_to_boss","replies":[{"id":"reply-1","direction":"boss_to_agent","body":"B","metadata":{"source":"api","provenance":{"version":1,"source":"api","signature":{"status":"not_configured"}}}}]}"#
    } else {
        r#"{"id":"ask-1","replies":[]}"#
    };
    let dropped = matches!(scenario, Scenario::DroppedBody) && index == 0;
    let length = body.len() + if dropped { 10 } else { 0 };
    let wire = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {length}\r\n\
         Connection: close\r\n\r\n{body}"
    );
    let _ = stream.write_all(wire.as_bytes()).await;
}

#[tokio::test]
async fn empty_windows_end_at_deadline_and_use_local_default() {
    let server = Server::start(Scenario::Empty).await;
    let start = Instant::now();
    let message = wait_for_reply(&server.client, "ask-1", 2)
        .await
        .expect("wait");
    let choices = ChoicePayload {
        options: Some(vec!["A".into(), "B".into()]),
        actions: Default::default(),
        default_option: Some("A".into()),
    };
    let result = AskResult::from_poll("ask-1", message.as_ref(), &choices);
    assert_eq!(
        serde_json::to_value(result).expect("result")["outcome"],
        "local_default"
    );
    assert!(start.elapsed() >= Duration::from_secs(2));
    assert!(start.elapsed() < Duration::from_secs(4));
    let paths = server.paths();
    assert_eq!(paths.len(), 3);
    assert!(paths[0].ends_with("timeout=2"));
    assert!(paths[1].ends_with("timeout=1"));
    assert_eq!(paths[2], "/api/messages/ask-1?replies=decisions");
}

#[tokio::test]
async fn deadline_cancels_a_stalled_poll() {
    let server = Server::start(Scenario::Stalled).await;
    let start = Instant::now();
    assert!(
        wait_for_reply(&server.client, "ask-1", 1)
            .await
            .expect("wait")
            .is_none()
    );
    assert!(start.elapsed() < Duration::from_secs(2));
    assert_eq!(
        server.paths(),
        [
            "/api/messages/ask-1/poll?timeout=1",
            "/api/messages/ask-1?replies=decisions"
        ]
    );
}

#[tokio::test]
async fn reply_stored_at_half_second_survives_in_flight_poll_cancellation() {
    let server = Server::start(Scenario::InsidePoll).await;
    let message = wait_for_reply(&server.client, "ask-1", 2)
        .await
        .expect("wait")
        .expect("reply");
    assert_eq!(
        message.replies.expect("replies")[0].body.as_deref(),
        Some("B")
    );
    assert_eq!(
        server.paths(),
        [
            "/api/messages/ask-1/poll?timeout=2",
            "/api/messages/ask-1?replies=decisions"
        ]
    );
}

#[tokio::test]
async fn reply_stored_during_deadline_ending_backoff_is_reconciled() {
    let server = Server::start(Scenario::Backoff).await;
    let message = wait_for_reply(&server.client, "ask-1", 2)
        .await
        .expect("wait")
        .expect("reply");
    assert_eq!(
        message.replies.expect("replies")[0].body.as_deref(),
        Some("B")
    );
    assert_eq!(
        server.paths().last().map(String::as_str),
        Some("/api/messages/ask-1?replies=decisions")
    );
}

#[tokio::test]
async fn dropped_response_body_retries_then_returns_reply() {
    let server = Server::start(Scenario::DroppedBody).await;
    let message = wait_for_reply(&server.client, "ask-1", 5)
        .await
        .expect("retry")
        .expect("reply");
    assert_eq!(
        message.replies.expect("replies")[0].body.as_deref(),
        Some("B")
    );
    assert_eq!(server.paths().len(), 2);
    assert!(server.paths().iter().all(|path| path.contains("/poll?")));
}

#[tokio::test]
async fn malformed_json_aborts_without_retry() {
    let server = Server::start(Scenario::MalformedJson).await;
    let error = wait_for_reply(&server.client, "ask-1", 5)
        .await
        .expect_err("malformed JSON");
    assert!(error.to_string().contains("decoding response body"));
    assert_eq!(server.paths().len(), 1);
}

#[path = "ask_wait_final_tests.rs"]
mod final_reads;
