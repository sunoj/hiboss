// Starts a Claude session and injects the shared HiBoss delivery instructions.
// Exports run; registers the session and checks inbound messages and receipts.
// Dependencies: session storage, hook helpers, and the embedded agent prompt.

use crate::session;
use std::{error::Error, fs, process::Command};
use super::{hook_helpers::*, hook_unacked::unacknowledged_outbound_warning, setup_agents::PROMPT};

pub(super) async fn run() -> Result<(), Box<dyn Error>> {
    clear_previous_session();
    let session_id = register_session().await;
    start_daemon_if_needed();
    println!("{PROMPT}");
    println!("CHOICES: Repeat singular --option or --action for each choice. Use --option-image LABEL=PATH for image comparisons. A timeout default is not a human decision or execution authorization.");
    println!("NOTIFY CONTEXT: send/ask accept --content for useful context and --summary for a non-sensitive private-mode push summary.");
    if crate::hiboss_dir::should_hint_register() {
        println!("Run: hiboss progress team register --display-name \"{}\"", session::project_name().replace('"', ""));
    }
    // Listing is read-only; peer notification requires explicit authorization.
    show_peer_sessions(&session_id).await;
    show_inbox();
    if let Ok(client) = build_client() {
        if let Some(warning) = unacknowledged_outbound_warning(&client, &session_id).await {
            println!("{warning}");
        }
    }
    Ok(())
}

fn clear_previous_session() {
    for path in [
        session::session_file_path(), session::asked_marker_path(), session::replied_marker_path(),
        session::ack_hint_shown_path(), session::stop_warned_marker_path(), session::broadcast_marker_path(),
        session::peers_active_marker_path(), session::broadcast_remind_ttl_path(), session::read_queue_path(),
        session::urgent_file_path(), session::daemon_pending_path(), session::ttl_file_path(),
        session::a2a_ttl_file_path(), session::resume_pending_marker_path(),
    ] { let _ = fs::remove_file(path); }
}

async fn register_session() -> String {
    let id = generate_session_id();
    let _ = session::write_session_id(&id);
    let branch = get_git_branch();
    let cwd = std::env::current_dir().ok().and_then(|path| path.file_name().map(|name| name.to_string_lossy().into_owned()));
    let label = match (get_repo_name(), &branch) {
        (Some(repo), Some(branch)) => Some(format!("{repo}/{branch}")),
        (Some(repo), None) => Some(repo),
        _ => None,
    };
    if let Ok(client) = build_client() {
        let _ = client.register_session(&id, branch.as_deref(), cwd.as_deref(), label.as_deref(), Some("working"), None).await;
    }
    id
}

fn show_inbox() {
    let count = get_inbox_count() + get_a2a_inbox_count();
    if count == 0 { return; }
    println!("You have {count} unread messages:");
    if let Ok(output) = Command::new("hiboss").args(["inbox"]).output() {
        print!("{}", String::from_utf8_lossy(&output.stdout));
    }
    println!("Handle these messages first. Reply with: hiboss reply <id> \"response\"");
}
