// Finds the one session a Claude runtime registered from another checkout, for commands run
// outside it. Exports session_from_other_checkout; ambiguous or shared identities borrow nothing.
// Dependencies: runtime, state, private, std::fs.

use super::SESSION;
use super::private::read_private;
use super::state::state_dir;
use crate::runtime::RuntimeIdentity;
use std::collections::BTreeSet;
use std::ffi::OsStr;
use std::fs;
use std::path::Path;

/// Several plain shells share this key, so its leaves never stand for one session.
const SHARED_KEY: &str = "default";

/// The session this Claude runtime holds under exactly one other project key. Codex and aid
/// register per project on their own, and several plain shells share the `default` key, so
/// they never borrow; two or more candidates are ambiguous, so none is chosen.
pub fn session_from_other_checkout() -> Option<String> {
    let identity = RuntimeIdentity::detect();
    if identity.runtime != "claude" || identity.session_key == SHARED_KEY {
        return None;
    }
    let own = state_dir()?;
    let project = own.parent()?;
    only_elsewhere(project.parent()?, project.file_name()?, own.file_name()?)
}

/// The single distinct session id `leaf` holds in project directories of `root` other than
/// `own_project`. Linked directories are not followed.
fn only_elsewhere(root: &Path, own_project: &OsStr, leaf: &OsStr) -> Option<String> {
    let real_dir = |path: &Path| fs::symlink_metadata(path).is_ok_and(|meta| meta.file_type().is_dir());
    let ids: BTreeSet<String> = fs::read_dir(root).ok()?.flatten().filter_map(|entry| {
        let directory = entry.path().join(leaf);
        if entry.file_name() == own_project || !real_dir(&entry.path()) || !real_dir(&directory) {
            return None;
        }
        let id = read_private(&directory.join(SESSION))?.trim().to_owned();
        (!id.is_empty()).then_some(id)
    }).collect();
    let mut ids = ids.into_iter();
    match (ids.next(), ids.next()) {
        (Some(id), None) => Some(id),
        _ => None,
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::super::state::leaf_name;
    use super::*;
    use std::path::PathBuf;

    fn root(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hiboss-elsewhere-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("root");
        dir
    }

    /// `project/<leaf for key>/session` holding `id`.
    fn session(root: &Path, project: &str, key: &str, id: &str) {
        let dir = root.join(project).join(leaf_name("claude", key).expect("leaf"));
        fs::create_dir_all(&dir).expect("leaf dir");
        fs::write(dir.join(SESSION), id).expect("session");
    }

    fn leaf(key: &str) -> String {
        leaf_name("claude", key).expect("leaf")
    }

    #[test]
    fn the_one_session_of_this_runtime_elsewhere_is_borrowed() {
        let dir = root("one");
        fs::create_dir_all(dir.join("cwd-project").join(leaf("me"))).expect("own empty leaf");
        session(&dir, "repo", "me", "sess-repo");
        session(&dir, "repo-peer", "someone-else", "sess-peer");
        let found = only_elsewhere(&dir, OsStr::new("cwd-project"), OsStr::new(&leaf("me")));
        assert_eq!(found.as_deref(), Some("sess-repo"));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn sessions_in_two_other_projects_are_ambiguous() {
        let dir = root("two");
        session(&dir, "repo-a", "me", "sess-a");
        session(&dir, "repo-b", "me", "sess-b");
        assert_eq!(only_elsewhere(&dir, OsStr::new("cwd-project"), OsStr::new(&leaf("me"))), None);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn own_project_empty_ids_and_links_are_never_chosen() {
        let (dir, target) = (root("skip"), root("skip-target"));
        session(&dir, "cwd-project", "me", "sess-own");
        session(&dir, "repo-blank", "me", " \n");
        session(&target, "repo-linked", "me", "sess-linked");
        std::os::unix::fs::symlink(target.join("repo-linked"), dir.join("repo-linked")).expect("link");
        let found = only_elsewhere(&dir, OsStr::new("cwd-project"), OsStr::new(&leaf("me")));
        assert_eq!(found, None);
        assert_eq!(only_elsewhere(&dir.join("missing"), OsStr::new("x"), OsStr::new(&leaf("me"))), None);
        let _ = fs::remove_dir_all(dir);
        let _ = fs::remove_dir_all(target);
    }
}
