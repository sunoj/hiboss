// Waits on a join request, resumes one left by an earlier run, and settles its outcome.
// Exports record, resume, wait_and_save, settle and abandon within onboarding.
// A dead poll token (approved, rejected, 404) removes the pending file; timeouts keep it.

use super::{
    SetupArgs, api,
    pending::{self, Pending},
    persistence, poll, selection, show_code,
};
use crate::config::Config;
use std::{error::Error, time::Duration};

/// Saves the pending request before polling; a failed write only costs resumability.
pub(super) fn record(plan: &selection::Plan, joined: &api::JoinResponse) {
    let entry = Pending::new(
        plan,
        &joined.request_id,
        &joined.poll_token,
        joined.state.verification_code.as_deref(),
    );
    if entry.save().is_err() {
        eprintln!(
            "Warning: could not save {}; this request cannot be resumed after setup exits",
            pending::path().display()
        );
    }
}

pub(super) async fn resume(
    args: &SetupArgs,
    config: &Config,
    entry: Pending,
) -> Result<selection::Plan, Box<dyn Error>> {
    if let Some(server) = args.server.as_deref() {
        if selection::normalize_server(server)? != entry.server {
            return Err(format!(
                "A join request for {} is pending; run hiboss setup without --server to resume it, or hiboss setup --abandon",
                entry.server
            )
            .into());
        }
    }
    if args.invite.is_some() {
        eprintln!("Note: ignoring --invite; the pending request does not need a new invite");
    }
    println!("Resuming the pending request from {}", entry.created_at);
    show_code(entry.verification_code.as_deref())?;
    let plan = entry.plan(selection::device_proof(config, &entry.server));
    wait_and_save(&plan, &entry.poll_token, args.wait).await?;
    Ok(plan)
}

pub(super) async fn wait_and_save(
    plan: &selection::Plan,
    token: &str,
    wait: u64,
) -> Result<(), Box<dyn Error>> {
    let http = api::http()?;
    let polled = poll::wait_for_approval(
        || api::status(&http, &plan.server, token),
        Duration::from_secs(3),
        Duration::from_secs(wait),
    )
    .await;
    let outcome = match polled {
        Ok(state) => settle(plan, state),
        Err(error) if error.is::<api::NotFound>() => Err(
            "HiBoss no longer knows the pending join request; run hiboss setup to request approval again"
                .into(),
        ),
        Err(error) => return Err(error),
    };
    if let Err(error) = pending::remove() {
        eprintln!("Warning: {error}");
    }
    outcome
}

/// Handles a terminal join state; only an undelivered approval saves credentials.
pub(super) fn settle(plan: &selection::Plan, state: api::JoinState) -> Result<(), Box<dyn Error>> {
    match state.status.as_str() {
        "approved" => persistence::persist(plan, state),
        "rejected" => Err("The boss rejected this machine's join request".into()),
        _ => Err("Invalid join status from HiBoss".into()),
    }
}

pub(super) fn abandon() -> Result<(), Box<dyn Error>> {
    if pending::remove()? {
        println!("Abandoned the pending join request; run hiboss setup to request approval again");
    } else {
        println!("No pending join request");
    }
    Ok(())
}
