// Session markers, TTL stamps, the urgent notice and the read queue used by CLI hooks.
// Exports marker helpers and the names SessionStart clears; depends on private state I/O.
use super::*;

const ASKED: &str = "asked";
const STOP_WARNED: &str = "stop-warned";
const RESUME_PENDING: &str = "resume-pending";
const REPLIED: &str = "replied";
const BROADCAST: &str = "broadcast";
const PEERS_ACTIVE: &str = "peers-active";
pub const BROADCAST_REMIND: &str = "broadcast-remind";
const READ_QUEUE: &str = "read-queue";
const ACK_HINT: &str = "ack-hint";

/// Everything SessionStart clears, so a resumed session id never inherits stale markers.
pub fn clear_session_markers() {
    for name in [
        SESSION, ASKED, REPLIED, ACK_HINT, STOP_WARNED, BROADCAST, PEERS_ACTIVE, BROADCAST_REMIND,
        READ_QUEUE, URGENT, DAEMON_PENDING, URGENT_CHECK, A2A_CHECK, RESUME_PENDING,
    ] {
        remove_state(name);
    }
}

fn mark(name: &str) {
    let _ = write_state(name, "1");
}

fn is_marked(name: &str) -> bool {
    read_state(name).is_some()
}

/// Record that `hiboss ask` was called this session.
pub fn mark_asked() {
    mark(ASKED);
}

/// Check whether `hiboss ask` was called this session.
pub fn has_asked() -> bool {
    is_marked(ASKED)
}

/// Marker: stop hook already warned once this session — don't block again.
pub fn mark_stop_warned() {
    mark(STOP_WARNED);
}

pub fn has_stop_warned() -> bool {
    is_marked(STOP_WARNED)
}

/// Record that the Stop hook parked this session as "waiting" (idle, awaiting the boss).
/// The next background heartbeat consumes it so a session that resumed work is flipped back
/// to "working". Existence flag only — never printed into agent context.
pub fn mark_resume_pending() {
    mark(RESUME_PENDING);
}

/// Consume the resume-pending marker: true (and deleted) when the session was parked as
/// waiting. The next bg-check only runs because active work resumed, so consuming it there
/// is the resume signal.
pub fn take_resume_pending() -> bool {
    take_state(RESUME_PENDING).is_some()
}

/// Clear the resume-pending marker without acting on it — a manually set status
/// (`hiboss ss`) wins, so bg-check must not later override it with "working".
pub fn clear_resume_pending() {
    remove_state(RESUME_PENDING);
}

/// Record that agent sent a reply/reaction after asking.
pub fn mark_replied() {
    if has_asked() {
        mark(REPLIED);
    }
}

/// Check whether agent replied after asking.
pub fn has_replied() -> bool {
    is_marked(REPLIED)
}

/// Record that agent broadcast to peers this session.
pub fn mark_broadcast() {
    mark(BROADCAST);
}

/// Check whether agent has broadcast to peers this session.
pub fn has_broadcast() -> bool {
    is_marked(BROADCAST)
}

/// Record that peer sessions were detected during this session.
pub fn mark_peers_active() {
    mark(PEERS_ACTIVE);
}

/// Check whether peer sessions were active during this session.
pub fn had_peers_active() -> bool {
    is_marked(PEERS_ACTIVE)
}

/// True when the epoch-seconds stamp in `name` is missing, unreadable or older than `ttl`.
pub fn is_ttl_expired(name: &str, now: u64, ttl: u64) -> bool {
    match read_state(name).and_then(|content| content.trim().parse::<u64>().ok()) {
        Some(last) => now.saturating_sub(last) >= ttl,
        None => true,
    }
}

/// Stamp `name` with the current epoch seconds.
pub fn stamp_ttl(name: &str, now: u64) {
    let _ = write_state(name, &now.to_string());
}

/// Take the urgent notice for printing, leaving it empty.
pub fn take_urgent() -> Option<String> {
    take_state(URGENT).filter(|content| !content.trim().is_empty())
}

/// Append to the urgent notice the next PostToolUse prints.
pub fn append_urgent(notice: &str) {
    let _ = append_state(URGENT, notice);
}

/// Append message IDs to the read queue (one per line).
pub fn queue_mark_read(ids: &[&str]) {
    if !ids.is_empty() {
        let _ = append_state(READ_QUEUE, &(ids.join("\n") + "\n"));
    }
}

/// Drain message IDs from the read queue. Returns IDs to mark.
pub fn drain_read_queue() -> Vec<String> {
    take_state(READ_QUEUE)
        .unwrap_or_default()
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_owned())
        .collect()
}

/// Show ack hint only once per session; returns true if hint should be printed.
pub fn should_show_ack_hint() -> bool {
    if is_marked(ACK_HINT) {
        return false;
    }
    mark(ACK_HINT);
    true
}
