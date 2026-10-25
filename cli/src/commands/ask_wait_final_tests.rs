// Verifies final reconciliation recovers stored replies and bounds transient retries.
// Uses the shared synthetic TCP fixture from ask_wait_tests.
// Dependencies: the waiter, Tokio tests, and HTTP failure scenarios.

use super::{Scenario, Server, wait_for_reply};

#[tokio::test]
async fn transient_final_read_returns_reply_stored_inside_deadline() {
    let server = Server::start(Scenario::FinalReadTransient).await;
    let message = wait_for_reply(&server.client, "ask-1", 1)
        .await
        .expect("one transient final-read 503 must retry")
        .expect("stored reply");
    assert_eq!(
        message.replies.expect("replies")[0].body.as_deref(),
        Some("B")
    );
    assert_eq!(
        server.paths(),
        [
            "/api/messages/ask-1/poll?timeout=1",
            "/api/messages/ask-1?replies=decisions",
            "/api/messages/ask-1?replies=decisions",
        ]
    );
}

#[tokio::test]
async fn final_read_stops_after_three_transient_failures() {
    let server = Server::start(Scenario::FinalReadUnavailable).await;
    let error = wait_for_reply(&server.client, "ask-1", 1)
        .await
        .expect_err("503");
    assert!(error.to_string().contains("503"));
    assert_eq!(server.paths().len(), 4);
}

#[tokio::test]
async fn final_read_does_not_retry_permanent_failure() {
    let server = Server::start(Scenario::FinalReadUnauthorized).await;
    let error = wait_for_reply(&server.client, "ask-1", 1)
        .await
        .expect_err("401");
    assert!(error.to_string().contains("401"));
    assert_eq!(server.paths().len(), 2);
}

#[tokio::test]
async fn final_read_asks_for_decisions_and_ignores_the_askers_own_reply() {
    let server = Server::start(Scenario::SelfReplyOnly).await;
    let message = wait_for_reply(&server.client, "ask-1", 1)
        .await
        .expect("wait");
    // CONTROL: one bounded poll, then one final read.
    assert_eq!(server.paths().len(), 2);
    assert!(message.is_none(), "the asker's own reply is not an answer");
    assert_eq!(server.paths()[1], "/api/messages/ask-1?replies=decisions");
}
