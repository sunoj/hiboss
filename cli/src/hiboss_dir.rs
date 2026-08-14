// Purpose: Manage the project-local .hiboss/ directory (team.json, state.json, avatar.png).
// Exports: LocalTeam, LocalState, hiboss_dir, team_json_path, avatar_png_path, state_json_path,
//          ensure_hiboss_dir, read_local_team, write_local_team, read_local_state,
//          write_local_state, team_json_hash, needs_sync, should_hint_register,
//          should_hint_register_in.
// Dependencies: crate::session, serde, std::fs, std::path.

use crate::session;
use serde::{Deserialize, Serialize};
use std::io;
use std::path::PathBuf;

/// Fields stored in `.hiboss/team.json` — the source of truth for team identity.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LocalTeam {
    pub handle: String,
    pub display_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bio: Option<String>,
    /// Filename relative to `.hiboss/` (typically `avatar.png`), or absent.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar: Option<String>,
}

/// Sync bookkeeping stored in `.hiboss/state.json` — gitignored, never hand-edited.
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct LocalState {
    /// FNV-1a hash of the last-synced `team.json` content.
    pub synced_hash: String,
}

/// Absolute path to the project-local `.hiboss/` directory.
pub fn hiboss_dir() -> PathBuf {
    PathBuf::from(session::project_dir()).join(".hiboss")
}

pub fn team_json_path() -> PathBuf {
    hiboss_dir().join("team.json")
}

pub fn avatar_png_path() -> PathBuf {
    hiboss_dir().join("avatar.png")
}

pub fn state_json_path() -> PathBuf {
    hiboss_dir().join("state.json")
}

/// Create `.hiboss/` if absent, and write the `state.json` gitignore rule on first creation.
pub fn ensure_hiboss_dir() -> io::Result<()> {
    ensure_hiboss_dir_at(&hiboss_dir())
}

/// Testable inner implementation taking an explicit directory path.
pub fn ensure_hiboss_dir_at(dir: &std::path::Path) -> io::Result<()> {
    let already_exists = dir.exists();
    std::fs::create_dir_all(dir)?;
    if !already_exists {
        std::fs::write(dir.join(".gitignore"), "state.json\n")?;
    }
    Ok(())
}

/// Read `team.json`, returning `None` if absent or unreadable.
pub fn read_local_team() -> Option<LocalTeam> {
    let content = std::fs::read_to_string(team_json_path()).ok()?;
    serde_json::from_str(&content).ok()
}

/// Write `team.json`, creating `.hiboss/` (with gitignore) if needed.
pub fn write_local_team(team: &LocalTeam) -> io::Result<()> {
    ensure_hiboss_dir()?;
    let json = serde_json::to_string_pretty(team)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;
    std::fs::write(team_json_path(), json + "\n")
}

/// Read `state.json`, returning a zeroed default if absent or unreadable.
pub fn read_local_state() -> LocalState {
    std::fs::read_to_string(state_json_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

/// Write `state.json`.
pub fn write_local_state(state: &LocalState) -> io::Result<()> {
    std::fs::create_dir_all(hiboss_dir())?;
    let json = serde_json::to_string(state)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;
    std::fs::write(state_json_path(), json + "\n")
}

/// FNV-1a hash of the current `team.json` content, or `None` if absent or unreadable.
pub fn team_json_hash() -> Option<String> {
    let content = std::fs::read_to_string(team_json_path()).ok()?;
    Some(fnv1a_hash(content.as_bytes()))
}

/// `true` when `team.json` exists and its hash differs from the last-synced hash.
pub fn needs_sync() -> bool {
    match team_json_hash() {
        None => false,
        Some(hash) => hash != read_local_state().synced_hash,
    }
}

/// `true` when a session-start hint should be printed:
/// `state.json` is present (project has posted before) and `team.json` is absent.
/// Filesystem-only — no network call, never panics.
pub fn should_hint_register() -> bool {
    should_hint_register_in(&hiboss_dir())
}

/// Testable inner implementation taking an explicit `.hiboss/` directory.
pub fn should_hint_register_in(dir: &std::path::Path) -> bool {
    dir.join("state.json").exists() && !dir.join("team.json").exists()
}

fn fnv1a_hash(bytes: &[u8]) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for &b in bytes {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{:016x}", h)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn make_temp_dir() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "hiboss-hd-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .subsec_nanos()
        ));
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }

    // --- should_hint_register_in ---

    #[test]
    fn hint_silent_when_no_hiboss_dir() {
        let base = make_temp_dir();
        // .hiboss/ does not exist
        assert!(!should_hint_register_in(&base.join(".hiboss")));
    }

    #[test]
    fn hint_one_line_when_state_exists_no_team() {
        let dir = make_temp_dir();
        fs::write(dir.join("state.json"), r#"{"synced_hash":""}"#).expect("write state");
        assert!(should_hint_register_in(&dir));
    }

    #[test]
    fn hint_silent_when_team_json_present() {
        let dir = make_temp_dir();
        fs::write(dir.join("state.json"), r#"{"synced_hash":""}"#).expect("write state");
        fs::write(dir.join("team.json"), r#"{"handle":"h","display_name":"H"}"#).expect("write team");
        assert!(!should_hint_register_in(&dir));
    }

    #[test]
    fn hint_silent_when_only_team_json_present() {
        // No state.json — project never posted progress
        let dir = make_temp_dir();
        fs::write(dir.join("team.json"), r#"{"handle":"h","display_name":"H"}"#).expect("write team");
        assert!(!should_hint_register_in(&dir));
    }

    // --- ensure_hiboss_dir_at ---

    #[test]
    fn ensure_writes_gitignore_on_first_creation() {
        let base = make_temp_dir();
        let dir = base.join(".hiboss");
        ensure_hiboss_dir_at(&dir).expect("ensure");
        let content = fs::read_to_string(dir.join(".gitignore")).expect("read gitignore");
        assert!(content.contains("state.json"));
    }

    #[test]
    fn ensure_does_not_overwrite_existing_gitignore() {
        let base = make_temp_dir();
        let dir = base.join(".hiboss");
        ensure_hiboss_dir_at(&dir).expect("first call");
        fs::write(dir.join(".gitignore"), "custom\n").expect("overwrite");
        ensure_hiboss_dir_at(&dir).expect("second call");
        let content = fs::read_to_string(dir.join(".gitignore")).expect("read");
        assert_eq!(content, "custom\n", "second call must not overwrite");
    }

    // --- LocalTeam serde ---

    #[test]
    fn local_team_omits_none_fields() {
        let t = LocalTeam {
            handle: "h".into(),
            display_name: "D".into(),
            bio: None,
            avatar: None,
        };
        let json = serde_json::to_string(&t).expect("serialize");
        assert!(!json.contains("bio"), "None bio must be omitted");
        assert!(!json.contains("avatar"), "None avatar must be omitted");
    }

    #[test]
    fn local_team_round_trips_all_fields() {
        let t = LocalTeam {
            handle: "myteam".into(),
            display_name: "My Team".into(),
            bio: Some("A bio".into()),
            avatar: Some("avatar.png".into()),
        };
        let json = serde_json::to_string(&t).expect("serialize");
        let back: LocalTeam = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back, t);
    }

    // --- LocalState serde ---

    #[test]
    fn local_state_defaults_to_empty_hash() {
        assert_eq!(LocalState::default().synced_hash, "");
    }

    #[test]
    fn local_state_round_trips() {
        let s = LocalState { synced_hash: "abc123".into() };
        let json = serde_json::to_string(&s).expect("serialize");
        let back: LocalState = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back, s);
    }

    // --- fnv1a_hash ---

    #[test]
    fn hash_is_deterministic() {
        assert_eq!(fnv1a_hash(b"hello"), fnv1a_hash(b"hello"));
    }

    #[test]
    fn hash_differs_on_different_input() {
        assert_ne!(fnv1a_hash(b"original content"), fnv1a_hash(b"edited content"),
            "hand-edit must change the hash");
    }
}
