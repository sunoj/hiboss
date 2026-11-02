// Detached note polling and local-only hook announcements.
// Exports refresh, announce, due and claim using private per-session state files.
use crate::{client::HiBossClient, session};
use serde::{Deserialize, Serialize};

const CHECK: &str = "note-check";
const PENDING: &str = "note-pending";
const ANNOUNCED: &str = "note-announced";

#[derive(Default, Deserialize, Serialize)]
struct Announcement {
    session: String,
    ids: Vec<String>,
    at: u64,
}
#[derive(Deserialize, Serialize)]
struct Pending {
    session: String,
    ids: Vec<String>,
    #[serde(default)]
    images: usize,
}

pub(super) fn due(now: u64) -> bool {
    session::is_ttl_expired(CHECK, now, 15)
}
pub(super) fn claim(now: u64) {
    session::stamp_ttl(CHECK, now);
}
pub(super) async fn refresh(client: &HiBossClient, sid: &str) {
    if let Ok(response) = client.session_notes(sid, false).await {
        let pending = Pending {
            session: sid.to_owned(),
            images: response.notes.iter().map(|note| note.images.len()).sum(),
            ids: response.notes.into_iter().map(|note| note.id).collect(),
        };
        if let Ok(content) = serde_json::to_string(&pending) {
            let _ = session::write_state(PENDING, &content);
        }
    }
}

fn should_announce(pending: &Pending, previous: &Announcement, now: u64) -> bool {
    !pending.ids.is_empty()
        && (pending.session != previous.session
            || pending.ids.iter().any(|id| !previous.ids.contains(id))
            || now.saturating_sub(previous.at) >= 300)
}

pub(super) fn announce(now: u64) {
    let Some(pending) =
        session::read_state(PENDING).and_then(|text| serde_json::from_str::<Pending>(&text).ok())
    else {
        return;
    };
    if session::read_session_id().as_deref() != Some(pending.session.as_str()) {
        return;
    }
    let previous = session::read_state(ANNOUNCED)
        .and_then(|text| serde_json::from_str::<Announcement>(&text).ok())
        .unwrap_or_default();
    if !should_announce(&pending, &previous, now) {
        return;
    }
    let notice = Announcement {
        session: pending.session,
        ids: pending.ids,
        at: now,
    };
    let Ok(content) = serde_json::to_string(&notice) else {
        return;
    };
    if session::write_state(ANNOUNCED, &content).is_ok() {
        println!(
            "BOSS NOTE (留言): the boss left {} note(s) with {} image(s) for this session. Read them now: hiboss note read",
            notice.ids.len(),
            pending.images
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_ids_announce_and_unread_ids_repeat_only_after_five_minutes() {
        let mut pending = Pending {
            session: "s".into(),
            ids: vec!["a".into()],
            images: 0,
        };
        let previous = Announcement {
            session: "s".into(),
            ids: vec!["a".into()],
            at: 100,
        };
        assert!(!should_announce(&pending, &previous, 399));
        assert!(should_announce(&pending, &previous, 400));
        pending.ids.push("b".into());
        assert!(should_announce(&pending, &previous, 101));
        pending.ids.clear();
        assert!(!should_announce(&pending, &previous, 500));
    }

    #[test]
    fn announcements_do_not_carry_over_to_another_session() {
        let pending = Pending {
            session: "new".into(),
            ids: vec!["a".into()],
            images: 0,
        };
        let previous = Announcement {
            session: "old".into(),
            ids: vec!["a".into()],
            at: 100,
        };
        assert!(should_announce(&pending, &previous, 101));
    }
}
