// Waits across bounded poll windows until a reply or the ask's monotonic deadline.
// Exports wait_for_reply; retries transient HTTP and transport failures with backoff.
// Dependencies: HiBossClient, typed HTTP errors, and Tokio deadline timers.

use crate::client::{HiBossClient, HttpError};
use crate::types::Message;
use std::error::Error;
use std::time::Duration;
use tokio::time::{Instant, sleep_until, timeout_at};

const POLL_WINDOW_SECONDS: u32 = 300;
const RETRY_BACKOFF: Duration = Duration::from_secs(1);

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
            Ok(Ok(message))
                if message
                    .replies
                    .as_ref()
                    .is_some_and(|items| !items.is_empty()) =>
            {
                return Ok(Some(message));
            }
            Ok(Ok(_)) => {}
            Ok(Err(error)) if is_transient(error.as_ref()) => {
                eprintln!("hiboss: poll failed, retrying while waiting for reply: {error}");
            }
            Ok(Err(error)) => return Err(error),
            Err(_) => break,
        }
        sleep_until(deadline.min(Instant::now() + RETRY_BACKOFF)).await;
    }
    let message = client.get_message(id).await?;
    Ok(message
        .replies
        .as_ref()
        .is_some_and(|items| !items.is_empty())
        .then_some(message))
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
