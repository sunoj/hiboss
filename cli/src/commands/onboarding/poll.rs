// Polls device approval on a fixed interval; the deadline bounds the waits between polls only.
// Exports wait_for_approval, which returns the first approved or rejected state.
// An in-flight status fetch is never cancelled: it may carry the one-time key delivery.

use super::api::JoinState;
use std::{error::Error, future::Future, time::Duration};
use tokio::time::{Instant, sleep_until};

pub(super) async fn wait_for_approval<F, Fut>(
    mut fetch: F,
    interval: Duration,
    limit: Duration,
) -> Result<JoinState, Box<dyn Error>>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<JoinState, Box<dyn Error>>>,
{
    let deadline = Instant::now() + limit;
    loop {
        let next = Instant::now() + interval;
        if next > deadline {
            return Err(timed_out());
        }
        sleep_until(next).await;
        // The server clears the delivery in the same request that returns it, so dropping
        // this future after it was sent could strand the keys. The HTTP client bounds it.
        let state = fetch().await?;
        match state.status.as_str() {
            "approved" | "rejected" => return Ok(state),
            "pending" => {}
            _ => return Err("Invalid join status from HiBoss".into()),
        }
    }
}

fn timed_out() -> Box<dyn Error> {
    "Still waiting for approval; run `hiboss setup` again to keep waiting (the request stays valid)."
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn state(status: &str) -> JoinState {
        JoinState {
            status: status.into(),
            device_id: None,
            verification_code: None,
            delivered: false,
            profiles: vec![],
        }
    }

    #[tokio::test]
    async fn pending_requests_stop_at_the_deadline() {
        let pending = || async { Ok(state("pending")) };
        let error = wait_for_approval(pending, Duration::from_millis(1), Duration::from_millis(20))
            .await
            .err()
            .map(|error| error.to_string())
            .unwrap_or_default();
        assert!(error.contains("Still waiting for approval"));
    }

    #[tokio::test]
    async fn an_in_flight_fetch_that_outlives_the_deadline_still_returns_its_approval() {
        let slow_approval = || async {
            tokio::time::sleep(Duration::from_millis(60)).await;
            Ok(state("approved"))
        };
        let approved = wait_for_approval(
            slow_approval,
            Duration::from_millis(1),
            Duration::from_millis(20),
        )
        .await;
        assert_eq!(
            approved.map(|state| state.status).ok().as_deref(),
            Some("approved")
        );
    }
}
