// Finds the session this runtime registered from another checkout, for commands run outside it.
// Exports session_from_other_checkout; a send from a folder outside the registering repository
// (another directory, no git) still belongs to that session. Dependencies: state, private, std::fs.

use super::SESSION;
use super::private::read_private;
use super::state::{decode_leaf, state_dir};
use std::ffi::OsStr;
use std::fs;
use std::path::Path;
use std::time::SystemTime;

/// Several plain shells share this key, so its leaves never stand for one session.
const SHARED_KEY: &str = "default";

/// The session id held by this runtime's own leaf under another project key, newest first.
pub fn session_from_other_checkout() -> Option<String> {
    let own = state_dir()?;
    let leaf = own.file_name()?;
    let (_, key) = decode_leaf(leaf.to_str()?)?;
    if key == SHARED_KEY {
        return None;
    }
    let project = own.parent()?;
    newest_elsewhere(project.parent()?, project.file_name()?, leaf)
}

/// Among project directories of `root` other than `own_project`, the session id in `leaf`
/// whose `session` file was modified last. Linked directories are not followed.
fn newest_elsewhere(root: &Path, own_project: &OsStr, leaf: &OsStr) -> Option<String> {
    let real_dir = |path: &Path| fs::symlink_metadata(path).is_ok_and(|meta| meta.file_type().is_dir());
    let candidates = fs::read_dir(root).ok()?.flatten().filter_map(|entry| {
        let directory = entry.path().join(leaf);
        if entry.file_name() == own_project || !real_dir(&entry.path()) || !real_dir(&directory) {
            return None;
        }
        let path = directory.join(SESSION);
        let id = read_private(&path)?.trim().to_owned();
        let touched = fs::symlink_metadata(&path).ok()?.modified().ok()?;
        (!id.is_empty()).then_some((touched, id))
    });
    candidates.max_by_key(|(touched, _)| *touched).map(|(_, id)| id)
}

#[cfg(all(test, unix))]
mod tests {
    use super::super::state::leaf_name;
    use super::*;
    use std::path::PathBuf;
    use std::time::Duration;

    fn root(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hiboss-elsewhere-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("root");
        dir
    }

    /// `project/<leaf for key>/session` holding `id`, touched `age` seconds ago.
    fn session(root: &Path, project: &str, key: &str, id: &str, age: u64) {
        let dir = root.join(project).join(leaf_name("claude", key).expect("leaf"));
        fs::create_dir_all(&dir).expect("leaf dir");
        fs::write(dir.join(SESSION), id).expect("session");
        let file = fs::File::options().write(true).open(dir.join(SESSION)).expect("open");
        file.set_modified(SystemTime::now() - Duration::from_secs(age)).expect("mtime");
    }

    fn leaf(key: &str) -> String {
        leaf_name("claude", key).expect("leaf")
    }

    #[test]
    fn newest_session_of_the_same_runtime_in_another_project_wins() {
        let dir = root("newest");
        fs::create_dir_all(dir.join("cwd-project").join(leaf("me"))).expect("own empty leaf");
        session(&dir, "repo-old", "me", "sess-old", 300);
        session(&dir, "repo-new", "me", "sess-new", 10);
        session(&dir, "repo-peer", "someone-else", "sess-peer", 1);
        let found = newest_elsewhere(&dir, OsStr::new("cwd-project"), OsStr::new(&leaf("me")));
        assert_eq!(found.as_deref(), Some("sess-new"));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn own_project_empty_ids_and_links_are_never_chosen() {
        let (dir, target) = (root("skip"), root("skip-target"));
        session(&dir, "cwd-project", "me", "sess-own", 1);
        session(&dir, "repo-blank", "me", " \n", 1);
        session(&target, "repo-linked", "me", "sess-linked", 1);
        std::os::unix::fs::symlink(target.join("repo-linked"), dir.join("repo-linked")).expect("link");
        let found = newest_elsewhere(&dir, OsStr::new("cwd-project"), OsStr::new(&leaf("me")));
        assert_eq!(found, None);
        assert_eq!(newest_elsewhere(&dir.join("missing"), OsStr::new("x"), OsStr::new(&leaf("me"))), None);
        let _ = fs::remove_dir_all(dir);
        let _ = fs::remove_dir_all(target);
    }
}
