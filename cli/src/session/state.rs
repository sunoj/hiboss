// Locates per-session state at $TMPDIR/hiboss/<project_key>/<profile>-<session>-<hash>/.
// Exports git_common_dir, project_key, state_dir, short_host.
// Dependencies: git, config profile resolution, runtime detection, std::fs, libc.

use crate::runtime::RuntimeIdentity;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

static STATE_DIR: OnceLock<Option<PathBuf>> = OnceLock::new();

/// Canonical git common dir of the project; the main checkout and its worktrees share it.
pub fn git_common_dir() -> Option<PathBuf> {
    let directory = super::project_dir();
    let output = Command::new("git")
        .args(["-C", &directory, "rev-parse", "--git-common-dir"])
        .output()
        .ok()
        .filter(|output| output.status.success())?;
    let raw = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    if raw.is_empty() {
        return None;
    }
    fs::canonicalize(Path::new(&directory).join(raw)).ok()
}

/// FNV hash of the git common dir, or of the project directory outside a repository.
pub fn project_key() -> String {
    let source = git_common_dir()
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_else(super::project_dir);
    super::fnv1a_hash(&source)
}

/// This session's private state directory, created owner-only on first use. None, after one
/// warning, when any component fails validation: the caller then runs without session state.
pub fn state_dir() -> Option<PathBuf> {
    STATE_DIR.get_or_init(init_state_dir).clone()
}

fn init_state_dir() -> Option<PathBuf> {
    let profile = crate::config::active_profile_name().unwrap_or_else(|| "unconfigured".into());
    let session_key = RuntimeIdentity::detect().session_key;
    let mut dir = std::env::temp_dir();
    // Each component is validated before anything is created inside it, so a descendant is
    // never reached through an untrusted ancestor.
    for part in ["hiboss".to_owned(), project_key(), leaf_name(&profile, &session_key)] {
        dir.push(part);
        if let Err(err) = create_private_dir(&dir) {
            eprintln!(
                "hiboss: session state directory {} is unusable ({err}); continuing without session state",
                dir.display()
            );
            return None;
        }
    }
    Some(dir)
}

/// Readable prefix plus a hash of the exact pair, so distinct (profile, session) never share a name.
fn leaf_name(profile: &str, session_key: &str) -> String {
    let hash = super::fnv1a_hash(&format!("{profile}\0{session_key}"));
    format!("{}-{}-{hash}", path_safe(profile), path_safe(session_key))
}

fn path_safe(value: &str) -> String {
    value
        .chars()
        .take(48)
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

#[cfg(unix)]
fn create_private_dir(path: &Path) -> io::Result<()> {
    use std::os::unix::fs::{DirBuilderExt, MetadataExt};
    match fs::DirBuilder::new().mode(0o700).create(path) {
        Err(err) if err.kind() != io::ErrorKind::AlreadyExists => return Err(err),
        _ => {}
    }
    let meta = fs::symlink_metadata(path)?;
    let euid = unsafe { libc::geteuid() };
    if !meta.file_type().is_dir() || meta.uid() != euid || meta.mode() & 0o077 != 0 {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "not a 0700 directory owned by the current user",
        ));
    }
    Ok(())
}

#[cfg(not(unix))]
fn create_private_dir(path: &Path) -> io::Result<()> {
    fs::create_dir_all(path)
}

/// Short host name (up to the first dot), reported when a session registers.
pub fn short_host() -> Option<String> {
    #[cfg(unix)]
    let name = {
        let mut buffer = [0u8; 256];
        let rc = unsafe { libc::gethostname(buffer.as_mut_ptr().cast(), buffer.len()) };
        if rc != 0 {
            return None;
        }
        let end = buffer
            .iter()
            .position(|byte| *byte == 0)
            .unwrap_or(buffer.len());
        String::from_utf8_lossy(&buffer[..end]).into_owned()
    };
    #[cfg(not(unix))]
    let name = std::env::var("COMPUTERNAME").ok()?;
    let short = name.split('.').next().unwrap_or_default().trim();
    (!short.is_empty()).then(|| short.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_safe_replaces_separators() {
        assert_eq!(path_safe("a/b..c d"), "a_b__c_d");
        assert_eq!(path_safe("claude-1_x"), "claude-1_x");
    }

    #[test]
    fn leaf_name_is_unambiguous() {
        assert_ne!(leaf_name("a.b", "s"), leaf_name("a_b", "s"));
        assert_ne!(leaf_name("a-b", "c"), leaf_name("a", "b-c"));
        assert!(leaf_name("claude", "s1").starts_with("claude-s1-"));
    }

    #[cfg(unix)]
    #[test]
    fn rejects_exposed_and_linked_directories() {
        use std::os::unix::fs::PermissionsExt;
        let root = std::env::temp_dir().join(format!("hiboss-state-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let dir = root.join("open");
        create_private_dir(&root).expect("private root");
        create_private_dir(&dir).expect("private dir");
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o755)).expect("chmod");
        assert!(create_private_dir(&dir).is_err(), "0755 is not private");
        let link = root.join("link");
        std::os::unix::fs::symlink(&dir, &link).expect("symlink");
        assert!(create_private_dir(&link).is_err(), "a symlink is never followed");
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn short_host_has_no_domain() {
        if let Some(host) = short_host() {
            assert!(!host.contains('.') && !host.is_empty());
        }
    }
}
