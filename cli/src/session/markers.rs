// Session markers and read queues used by CLI hooks.
// Exports marker helpers; depends on private session paths and filesystem access.
use super::*;

/// Marker file: written by `hiboss ask`, checked by Stop hook.
pub fn asked_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-asked-{}", project_hash()))
}

/// Record that `hiboss ask` was called this session.
pub fn mark_asked() {
    let _ = fs::write(asked_marker_path(), "1");
}

/// Check whether `hiboss ask` was called this session.
pub fn has_asked() -> bool {
    asked_marker_path().exists()
}

/// Marker: stop hook already warned once this session — don't block again.
pub fn stop_warned_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-stop-warned-{}", project_hash()))
}

pub fn mark_stop_warned() {
    let _ = fs::write(stop_warned_marker_path(), "1");
}

pub fn has_stop_warned() -> bool {
    stop_warned_marker_path().exists()
}

/// Marker: the Stop hook parked this session as "waiting" (idle, awaiting the
/// boss). Set on Stop, consumed by the next background heartbeat so a session
/// that resumed work is flipped back to "working" instead of lingering as
/// waiting. Existence flag only — never printed into agent context.
pub fn resume_pending_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-resume-pending-{}", project_hash()))
}

/// Record that the Stop hook parked this session as waiting.
pub fn mark_resume_pending() {
    let _ = fs::write(resume_pending_marker_path(), "1");
}

/// Consume the resume-pending marker: returns true (and deletes it) when the
/// session was parked as waiting and should now be reset to working. The next
/// bg-check only runs because active work resumed, so consuming it there is the
/// resume signal.
pub fn take_resume_pending() -> bool {
    let path = resume_pending_marker_path();
    if path.exists() {
        let _ = fs::remove_file(&path);
        true
    } else {
        false
    }
}

/// Clear the resume-pending marker without acting on it — a manually set status
/// (`hiboss ss`) wins, so bg-check must not later override it with "working".
pub fn clear_resume_pending() {
    let _ = fs::remove_file(resume_pending_marker_path());
}

/// Marker file: written by send/reply/react after an ask, checked by Stop hook.
pub fn replied_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-replied-{}", project_hash()))
}

/// Record that agent sent a reply/reaction after asking.
pub fn mark_replied() {
    if has_asked() {
        let _ = fs::write(replied_marker_path(), "1");
    }
}

/// Check whether agent replied after asking.
pub fn has_replied() -> bool {
    replied_marker_path().exists()
}

/// Marker file: written when agent broadcasts to peers, checked by Stop hook.
pub fn broadcast_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-broadcast-{}", project_hash()))
}

/// Record that agent broadcast to peers this session.
pub fn mark_broadcast() {
    let _ = fs::write(broadcast_marker_path(), "1");
}

/// Check whether agent has broadcast to peers this session.
pub fn has_broadcast() -> bool {
    broadcast_marker_path().exists()
}

/// Marker file: tracks whether peers were active during this session.
pub fn peers_active_marker_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-peers-active-{}", project_hash()))
}

/// Record that peer sessions were detected during this session.
pub fn mark_peers_active() {
    let _ = fs::write(peers_active_marker_path(), "1");
}

/// Check whether peer sessions were active during this session.
pub fn had_peers_active() -> bool {
    peers_active_marker_path().exists()
}

/// TTL file for broadcast reminders (avoid spamming every PostToolUse).
pub fn broadcast_remind_ttl_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-broadcast-remind-{}", project_hash()))
}

/// Queue file for message IDs to be marked as read by bg-check.
pub fn read_queue_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-read-queue-{}", project_hash()))
}

/// Append message IDs to the read queue (one per line).
pub fn queue_mark_read(ids: &[&str]) {
    if ids.is_empty() {
        return;
    }
    let content = ids.join("\n") + "\n";
    // Append to file
    let path = read_queue_path();
    let existing = fs::read_to_string(&path).unwrap_or_default();
    let _ = write_private(&path, &format!("{}{}", existing, content));
}

/// Drain message IDs from the read queue. Returns IDs to mark.
pub fn drain_read_queue() -> Vec<String> {
    let path = read_queue_path();
    let tmp = path.with_extension("draining");
    if fs::rename(&path, &tmp).is_err() {
        return vec![];
    }
    let content = fs::read_to_string(&tmp).unwrap_or_default();
    let _ = fs::remove_file(&tmp);
    content
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.to_owned())
        .collect()
}

/// Marker file: tracks whether the ack hint has been shown this session.
pub fn ack_hint_shown_path() -> PathBuf {
    PathBuf::from(format!("/tmp/hiboss-ack-hint-{}", project_hash()))
}

/// Show ack hint only once per session; returns true if hint should be printed.
pub fn should_show_ack_hint() -> bool {
    let path = ack_hint_shown_path();
    if path.exists() {
        return false;
    }
    let _ = fs::write(&path, "1");
    true
}
