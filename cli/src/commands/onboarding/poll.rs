// Polls device approval on a fixed interval with a bounded overall deadline.
// Exports wait_for_approval; generic fetch allows short deterministic deadline tests.
// Dependencies: tokio time and typed JoinState, with no testing runtime flags.

use super::api::JoinState;
use std::{error::Error, future::Future, time::Duration};
use tokio::time::{Instant, sleep_until, timeout_at};

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
        timeout_at(deadline, sleep_until(next))
            .await
            .map_err(|_| timed_out())?;
        let state = timeout_at(deadline, fetch())
            .await
            .map_err(|_| timed_out())??;
        match state.status.as_str() {
            "approved" => return Ok(state),
            "rejected" => return Err("The boss rejected this machine's join request".into()),
            "pending" => {}
            _ => return Err("Invalid join status from HiBoss".into()),
        }
    }
}

fn timed_out() -> Box<dyn Error> {
    "Timed out waiting for approval after 30 minutes; mint a new invite and run setup again".into()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn pending_and_stalled_requests_respect_deadline() {
        let limit = Duration::from_millis(20);
        let pending = || async {
            Ok(JoinState {
                status: "pending".into(),
                device_id: None,
                verification_code: None,
                delivered: false,
                profiles: vec![],
            })
        };
        let error = wait_for_approval(pending, Duration::from_millis(1), limit)
            .await
            .err()
            .unwrap();
        assert!(error.to_string().contains("Timed out waiting for approval"));
        let stalled =
            || async { std::future::pending::<Result<JoinState, Box<dyn Error>>>().await };
        assert!(
            wait_for_approval(stalled, Duration::from_millis(1), limit)
                .await
                .is_err()
        );
    }
}
