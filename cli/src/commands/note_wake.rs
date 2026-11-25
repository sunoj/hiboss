// Wakes an idle Claude Code session for a boss note (留言) the way a reply does: once per note,
// with a count and a command only, never a note's text. Polls under the hook's 15 s notes TTL.
// Exports NOTE_TICK, check and notice; deps: hook_notes, daemon_wake::Inbox, session markers.

use super::daemon_wake::{Inbox, is_gone};
use super::hook_notes;
use crate::{client::HiBossClient, session};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Notes this session was already woken for; kept to the ids that are still pending.
const NOTE_WOKEN: &str = "note-woken";
/// How often the daemon looks at the local idle marker and TTL; the network poll stays at 15 s.
pub(crate) const NOTE_TICK: Duration = Duration::from_secs(2);

/// One daemon tick. While the session is idle and the notes TTL has run out, reads the pending
/// notes and wakes the session for any it was not woken for yet. True when its process is gone.
pub(crate) async fn check(client: &HiBossClient, inbox: &Inbox, session_id: &str) -> bool {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    if !session::is_idle() || !hook_notes::due(now) {
        return false;
    }
    hook_notes::claim(now);
    let Some(pending) = hook_notes::refresh(client, session_id).await else {
        return false;
    };
    let Some(text) = notice(&pending) else {
        return false;
    };
    match inbox.push(text).await {
        Ok(()) => false,
        Err(err) => {
            eprintln!("hiboss: note wake not delivered: {err}");
            is_gone(&err)
        }
    }
}

/// The wake notice for the pending notes, or None when every one already woke the session or
/// the session is no longer idle. An unread note never wakes it twice: that would repeat on
/// every turn the agent ends without reading it.
pub(crate) fn notice(pending: &[String]) -> Option<String> {
    let recorded = session::read_state(NOTE_WOKEN).unwrap_or_default();
    let woken: Vec<&str> = recorded.lines().filter(|id| pending.iter().any(|p| p == id)).collect();
    let fresh = pending.iter().filter(|id| !woken.contains(&id.as_str())).count();
    if fresh == 0 {
        // Read notes drop out, so the record never outgrows the pending list.
        if woken.len() != recorded.lines().count() {
            let _ = session::write_state(NOTE_WOKEN, &woken.join("\n"));
        }
        return None;
    }
    session::take_idle()?;
    let _ = session::write_state(NOTE_WOKEN, &pending.join("\n"));
    Some(format!(
        "[hiboss] The boss left {fresh} new note(s) (留言) for this session while it was idle. \
         Read them with `hiboss note read`, then answer each with `hiboss note reply <note-id> \"...\"`."
    ))
}
