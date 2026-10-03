// Registers this session with the server and repairs a session that belongs to another agent.
// Exports register_new_session, is_foreign_session, heal_foreign_session, send_with_session_heal.
// Dependencies: HiBossClient, session state, hook helpers for git context.

use super::hook_helpers::{generate_session_id, get_git_branch};
use crate::client::HiBossClient;
use crate::session;
use crate::types::{SendRequest, SendResponse};
use std::error::Error;

/// Server text for a session id registered by a different agent.
const FOREIGN_SESSION: &str = "session does not belong to calling agent";

/// Generate, persist and register a fresh session id in this session's state directory.
pub(crate) async fn register_new_session(client: &HiBossClient) -> Result<String, Box<dyn Error>> {
    let id = generate_session_id();
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

pub(crate) fn is_foreign_session(err: &dyn Error) -> bool {
    err.to_string().contains(FOREIGN_SESSION)
}

/// Replace a session the server attributes to another agent with one for the current profile.
pub(crate) async fn heal_foreign_session(client: &HiBossClient) -> Result<String, Box<dyn Error>> {
    let id = register_new_session(client).await?;
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

    #[test]
    fn recognises_the_server_rejection() {
        let err: Box<dyn Error> =
            "request failed (400 Bad Request): session does not belong to calling agent".into();
        assert!(is_foreign_session(err.as_ref()));
        let other: Box<dyn Error> = "request failed (400 Bad Request): body is required".into();
        assert!(!is_foreign_session(other.as_ref()));
    }
}
