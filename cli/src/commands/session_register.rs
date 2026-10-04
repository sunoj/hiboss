// Registers this session with the server and repairs a session that belongs to another agent.
// Exports register_new_session, is_foreign_session, heal_foreign_session, send_with_session_heal.
// Dependencies: HiBossClient, session state, hook helpers for git context.

use super::hook_helpers::{generate_session_id, get_git_branch, restart_daemon_if_running};
use crate::client::{HiBossClient, HttpError};
use crate::session;
use crate::types::{SendRequest, SendResponse};
use std::error::Error;

/// Exact plain-text body of the server's 400 for a session id registered by a different agent.
const FOREIGN_SESSION: &str = "session does not belong to calling agent";

/// Generate, persist and register a fresh session id in this session's state directory.
pub(crate) async fn register_new_session(client: &HiBossClient) -> Result<String, Box<dyn Error>> {
    let id = generate_session_id();
    // The runtime marker is what lets a dispatched sibling tell this directory apart.
    session::write_state(session::RUNTIME, &crate::runtime::RuntimeIdentity::detect().runtime)?;
    session::write_session_id(&id)?;
    let branch = get_git_branch();
    let project = session::resolve_project(None).slug;
    let label = match &branch {
        Some(branch) => format!("{project}/{branch}"),
        None => project,
    };
    let cwd = session::project_dir();
    client
        .register_session(
            &id,
            branch.as_deref(),
            Some(&cwd),
            Some(&label),
            Some("working"),
            None,
        )
        .await?;
    Ok(id)
}

pub(crate) fn is_foreign_session(err: &(dyn Error + 'static)) -> bool {
    err.downcast_ref::<HttpError>().is_some_and(|err| {
        err.status == reqwest::StatusCode::BAD_REQUEST && err.body == FOREIGN_SESSION
    })
}

/// Replace a session the server attributes to another agent with one for the current profile.
/// A running daemon is restarted so its SSE subscription follows the new session id.
pub(crate) async fn heal_foreign_session(client: &HiBossClient) -> Result<String, Box<dyn Error>> {
    let id = register_new_session(client).await?;
    restart_daemon_if_running();
    eprintln!(
        "hiboss: session belonged to another agent; registered session {id} for this profile and retried"
    );
    Ok(id)
}

/// Send once; on a foreign-session rejection, register a fresh session and retry once.
pub(crate) async fn send_with_session_heal(
    client: &HiBossClient,
    request: &mut SendRequest,
) -> Result<SendResponse, Box<dyn Error>> {
    match client.send_message(request).await {
        Err(err) if request.session_id.is_some() && is_foreign_session(err.as_ref()) => {
            request.session_id = Some(heal_foreign_session(client).await?);
            client.send_message(request).await
        }
        outcome => outcome,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use reqwest::StatusCode;

    fn rejection(status: StatusCode, body: &str, request_id: Option<&str>) -> Box<dyn Error> {
        let request_id = request_id.map(str::to_owned);
        Box::new(HttpError { prefix: "request failed", status, request_id, body: body.to_owned() })
    }

    #[test]
    fn heals_only_the_exact_400_rejection() {
        assert!(is_foreign_session(rejection(StatusCode::BAD_REQUEST, FOREIGN_SESSION, None).as_ref()));
        let longer = format!("{FOREIGN_SESSION}: other");
        assert!(!is_foreign_session(rejection(StatusCode::BAD_REQUEST, &longer, None).as_ref()));
        assert!(!is_foreign_session(rejection(StatusCode::INTERNAL_SERVER_ERROR, FOREIGN_SESSION, None).as_ref()));
        let in_request_id = rejection(StatusCode::BAD_REQUEST, "bad", Some(FOREIGN_SESSION));
        assert!(!is_foreign_session(in_request_id.as_ref()));
        let formatted: Box<dyn Error> = rejection(StatusCode::BAD_REQUEST, FOREIGN_SESSION, None).to_string().into();
        assert!(!is_foreign_session(formatted.as_ref()), "a formatted message is never matched");
    }
}
