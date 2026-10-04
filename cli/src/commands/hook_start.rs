// Starts a Claude session and injects the shared HiBoss delivery instructions.
// Exports run; registers the session and checks inbound messages and receipts.
// Dependencies: session storage, hook helpers, and the embedded agent prompt.

use crate::session;
use std::{error::Error, process::Command};
use super::{hook_helpers::*, hook_unacked::unacknowledged_outbound_warning, session_register::register_new_session, setup_agents::PROMPT};

pub(super) async fn run() -> Result<(), Box<dyn Error>> {
    // Without a usable state directory nothing could hold the session id, spool or pid.
    let session_id = match session::state_dir() {
        Some(_) => {
            session::clear_session_markers();
            let session_id = register_session().await;
            if let Err(err) = start_daemon_if_needed() {
                eprintln!("hiboss: daemon start failed: {err}");
            }
            session_id
        }
        None => String::new(),
    };
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

async fn register_session() -> String {
    let registered = match build_client() {
        Ok(client) => register_new_session(&client).await,
        Err(err) => Err(err),
    };
    registered.unwrap_or_else(|err| {
        // Hooks swallow failures; this one leaves send/progress unattributed, so say so.
        eprintln!("hiboss: session registration failed: {err}");
        session::read_session_id().unwrap_or_default()
    })
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
