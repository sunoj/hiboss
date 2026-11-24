// Waits across bounded poll windows until a reply or the ask's monotonic deadline.
// Exports wait_for_reply, spool_reply; retries transient HTTP and transport failures.
// Dependencies: HiBossClient, typed HTTP errors, and Tokio deadline timers.

use super::ask_result::decision_reply;
use crate::client::{HiBossClient, HttpError};
use crate::types::Message;
use std::error::Error;
use std::time::Duration;
use tokio::time::{Instant, sleep_until, timeout_at};

const POLL_WINDOW_SECONDS: u32 = 300;
const RETRY_BACKOFF: Duration = Duration::from_secs(1);
const FINAL_READ_ATTEMPTS: u32 = 3;

pub(crate) async fn wait_for_reply(
    client: &HiBossClient,
    id: &str,
    timeout: u32,
) -> Result<Option<Message>, Box<dyn Error>> {
    let deadline = Instant::now() + Duration::from_secs(u64::from(timeout));
    while Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(Instant::now());
        let window = remaining
            .as_secs_f64()
            .ceil()
            .min(f64::from(POLL_WINDOW_SECONDS)) as u32;
        match timeout_at(deadline, client.poll_reply(id, window)).await {
            Ok(Ok(message)) if decision_reply(&message).is_some() => return Ok(Some(message)),
            Ok(Ok(_)) => {}
            Ok(Err(error)) if is_transient(error.as_ref()) => {
                eprintln!("hiboss: poll failed, retrying while waiting for reply: {error}");
            }
            Ok(Err(error)) => return Err(error),
            Err(_) => break,
        }
        sleep_until(deadline.min(Instant::now() + RETRY_BACKOFF)).await;
    }
    let message = reconcile_reply(client, id).await?;
    Ok(decision_reply(&message).is_some().then_some(message))
}

/// Hands the reply to the session spool as well as to the waiter's output. A waiter that was
/// detached or redirected to a file still gets its answer to the agent: the next tool call
/// shows it, and Stop wakes an idle session for it. The daemon cannot be relied on here,
/// because the waiter marks the reply read before the stream's next poll sees it.
pub(crate) fn spool_reply(ask: &Message) {
    let Some(reply) = decision_reply(ask) else { return };
    let mut entry = reply.clone();
    entry.reply_to = entry.reply_to.or_else(|| Some(ask.id.clone()));
    entry.target_session_id = entry.target_session_id.or_else(|| ask.session_id.clone());
    if let Ok(line) = serde_json::to_string(&entry) {
        let _ = crate::session::append_state(crate::session::DAEMON_PENDING, &format!("{line}\n"));
    }
}

async fn reconcile_reply(client: &HiBossClient, id: &str) -> Result<Message, Box<dyn Error>> {
    let mut attempt = 0;
    loop {
        attempt += 1;
        match client.get_decisions(id).await {
            Ok(message) => return Ok(message),
            Err(error) if attempt < FINAL_READ_ATTEMPTS && is_transient(error.as_ref()) => {
                eprintln!("hiboss: final reply read failed, retrying: {error}");
                sleep_until(Instant::now() + RETRY_BACKOFF).await;
            }
            Err(error) => return Err(error),
        }
    }
}

fn is_transient(error: &(dyn Error + 'static)) -> bool {
    if let Some(error) = error.downcast_ref::<HttpError>() {
        return error.status.is_server_error()
            || error.status == reqwest::StatusCode::REQUEST_TIMEOUT
            || error.status == reqwest::StatusCode::TOO_MANY_REQUESTS;
    }
    error.downcast_ref::<reqwest::Error>().is_some_and(|error| {
        error.is_timeout()
            || error.is_connect()
            || error.is_request()
            || error.is_body()
            || (error.is_decode() && !is_json_error(error))
    })
}

fn is_json_error(error: &(dyn Error + 'static)) -> bool {
    let mut source = error.source();
    while let Some(error) = source {
        if error.is::<serde_json::Error>() {
            return true;
        }
        source = error.source();
    }
    false
}

#[cfg(test)]
#[path = "ask_wait_tests.rs"]
mod tests;
