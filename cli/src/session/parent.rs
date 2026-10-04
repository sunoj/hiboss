// Finds the session a dispatched (aid) agent registers under: the most recently touched
// non-dispatched sibling session directory in the same project_key directory.
// Exports parent_session_id and the RUNTIME marker name; dependencies: state, private, std::fs.

use super::SESSION;
use super::private::read_private;
use super::state::{decode_leaf, state_dir};
use std::ffi::OsStr;
use std::fs;
use std::path::Path;
use std::time::SystemTime;

/// State file naming the runtime that registered the directory's session (`claude`, `aid`,
/// ...). A leaf's name cannot tell an aid task id from a Claude session id, so this marker is
/// what makes a dispatched directory distinguishable; a leaf without it is never a parent.
pub const RUNTIME: &str = "runtime";

/// The parent session id for this session, or None when no sibling qualifies.
pub fn parent_session_id() -> Option<String> {
    let own = state_dir()?;
    newest_parent(own.parent()?, own.file_name()?)
}

/// Among the leaves of `project` other than `own_leaf`, the session id of the non-dispatched
/// one whose `session` file was modified last.
fn newest_parent(project: &Path, own_leaf: &OsStr) -> Option<String> {
    let entries = fs::read_dir(project).ok()?.flatten();
    let candidates = entries.filter_map(|entry| {
        let is_dir = entry.file_type().ok()?.is_dir();
        let name = entry.file_name();
        if !is_dir || name == own_leaf || decode_leaf(name.to_str()?).is_none() {
            return None;
        }
        candidate(&entry.path())
    });
    candidates.max_by_key(|(touched, _)| *touched).map(|(_, id)| id)
}

/// (mtime of `session`, session id) for a leaf registered by a non-dispatched runtime.
fn candidate(leaf: &Path) -> Option<(SystemTime, String)> {
    let runtime = read_private(&leaf.join(RUNTIME))?;
    if matches!(runtime.trim(), "" | "aid") {
        return None;
    }
    let path = leaf.join(SESSION);
    let id = read_private(&path)?.trim().to_owned();
    let touched = fs::symlink_metadata(&path).ok()?.modified().ok()?;
    (!id.is_empty()).then_some((touched, id))
}

#[cfg(all(test, unix))]
mod tests {
    use super::super::state::leaf_name;
    use super::*;
    use std::path::PathBuf;
    use std::time::Duration;

    fn project(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hiboss-parent-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("project dir");
        dir
    }

    /// A leaf for ("claude", key) holding `runtime` and `session`, touched `age` seconds ago.
    fn leaf(project: &Path, key: &str, runtime: Option<&str>, id: &str, age: u64) -> String {
        let name = leaf_name("claude", key).expect("short leaf");
        let dir = project.join(&name);
        fs::create_dir_all(&dir).expect("leaf");
        if let Some(runtime) = runtime {
            fs::write(dir.join(RUNTIME), runtime).expect("runtime");
        }
        fs::write(dir.join(SESSION), id).expect("session");
        let file = fs::File::options().write(true).open(dir.join(SESSION)).expect("open");
        file.set_modified(SystemTime::now() - Duration::from_secs(age)).expect("mtime");
        name
    }

    #[test]
    fn newest_non_dispatched_sibling_wins() {
        let dir = project("newest");
        let own = leaf(&dir, "task-own", Some("aid"), "own", 0);
        leaf(&dir, "old", Some("claude"), "sess-old", 300);
        leaf(&dir, "new", Some("none"), "sess-new", 100);
        leaf(&dir, "task-peer", Some("aid"), "sess-aid", 10);
        assert_eq!(newest_parent(&dir, OsStr::new(&own)).as_deref(), Some("sess-new"));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn own_unmarked_and_malformed_leaves_are_never_chosen() {
        let dir = project("skip");
        let own = leaf(&dir, "self", Some("claude"), "own", 0);
        leaf(&dir, "legacy", None, "sess-legacy", 5);
        leaf(&dir, "blank", Some(" \n"), "sess-blank", 5);
        let stray = dir.join("not-a-leaf");
        fs::create_dir_all(&stray).expect("stray");
        fs::write(stray.join(RUNTIME), "claude").expect("runtime");
        fs::write(stray.join(SESSION), "sess-stray").expect("session");
        assert_eq!(newest_parent(&dir, OsStr::new(&own)), None);
        leaf(&dir, "empty", Some("claude"), "  ", 1);
        assert_eq!(newest_parent(&dir, OsStr::new(&own)), None, "an empty session id is no parent");
        assert_eq!(newest_parent(&dir.join("missing"), OsStr::new(&own)), None);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn a_linked_leaf_is_not_followed() {
        let (dir, target) = (project("link"), project("link-target"));
        let real = leaf(&target, "real", Some("claude"), "sess-linked", 1);
        let name = leaf_name("claude", "linked").expect("short leaf");
        std::os::unix::fs::symlink(target.join(real), dir.join(name)).expect("symlink");
        assert_eq!(newest_parent(&dir, OsStr::new("x")), None);
        let _ = fs::remove_dir_all(dir);
        let _ = fs::remove_dir_all(target);
    }
}
