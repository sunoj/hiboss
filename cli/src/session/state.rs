// Locates per-session state at <cache_dir>/hiboss/sessions/<project_key>/<hex profile>-<hex session>/.
// Exports git_common_dir, project_key, state_dir, short_host.
// Dependencies: git, dirs, config profile resolution, runtime detection, std::fs, libc.

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

/// This session's state directory, created on first use. None, after one warning, when it
/// cannot be created or is not a real directory owned by the caller: the caller then runs
/// without session state.
pub fn state_dir() -> Option<PathBuf> {
    STATE_DIR.get_or_init(init_state_dir).clone()
}

fn init_state_dir() -> Option<PathBuf> {
    let profile = crate::config::active_profile_name().unwrap_or_else(|| "unconfigured".into());
    let session_key = RuntimeIdentity::detect().session_key;
    let dir = leaf_name(&profile, &session_key).and_then(|leaf| {
        let root = dirs::cache_dir().ok_or_else(|| io::Error::other("no user cache directory"))?;
        let dir = root.join("hiboss").join("sessions").join(project_key()).join(leaf);
        create_private_dir(&dir).map(|()| dir)
    });
    match dir {
        Ok(dir) => Some(dir),
        Err(err) => {
            eprintln!("hiboss: session state directory is unusable ({err}); continuing without session state");
            None
        }
    }
}

/// Longest leaf name; real session keys (UUIDs, aid task ids) stay far below it.
const MAX_LEAF: usize = 200;

/// Lowercase hex of each part's UTF-8 bytes joined by `-`. Hex has no `-`, so the mapping is
/// injective: distinct (profile, session) pairs never share a directory.
fn leaf_name(profile: &str, session_key: &str) -> io::Result<String> {
    let hex = |value: &str| value.bytes().map(|byte| format!("{byte:02x}")).collect::<String>();
    let leaf = format!("{}-{}", hex(profile), hex(session_key));
    if leaf.len() > MAX_LEAF {
        let reason = format!("the hex-encoded profile and session key exceed {MAX_LEAF} bytes");
        return Err(io::Error::new(io::ErrorKind::InvalidInput, reason));
    }
    Ok(leaf)
}

/// Creates missing directories 0700 and leaves existing ones as they are; the leaf must be a
/// real directory, not a symlink, owned by the caller.
fn create_private_dir(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::{DirBuilderExt, MetadataExt};
        let named = |err: io::Error| io::Error::new(err.kind(), format!("{}: {err}", path.display()));
        fs::DirBuilder::new().recursive(true).mode(0o700).create(path).map_err(named)?;
        let meta = fs::symlink_metadata(path).map_err(named)?;
        if meta.file_type().is_dir() && meta.uid() == unsafe { libc::geteuid() } {
            return Ok(());
        }
        let reason = "not a directory owned by the current user";
        Err(named(io::Error::new(io::ErrorKind::PermissionDenied, reason)))
    }
    #[cfg(not(unix))]
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
    fn leaf_name_is_injective() {
        let leaf = |profile, session| leaf_name(profile, session).expect("short leaf");
        assert_ne!(leaf("a.b", "s"), leaf("a_b", "s"));
        assert_eq!((leaf("a-b", "c").as_str(), leaf("a", "b-c").as_str()), ("612d62-63", "61-622d63"));
        let long = "k".repeat(64);
        assert_ne!(leaf("p", &format!("{long}a")), leaf("p", &format!("{long}b")), "no truncation");
        assert!(leaf_name("p", &"k".repeat(100)).is_err(), "over 200 bytes is refused");
    }

    #[cfg(unix)]
    #[test]
    fn rejects_linked_directories_and_keeps_existing_modes() {
        use std::os::unix::fs::PermissionsExt;
        let root = std::env::temp_dir().join(format!("hiboss-state-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let (dir, link) = (root.join("a/b"), root.join("link"));
        create_private_dir(&dir).expect("private dir");
        assert_eq!(fs::metadata(&root).expect("root").permissions().mode() & 0o777, 0o700);
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o750)).expect("chmod");
        create_private_dir(&dir).expect("an existing directory is used as it is");
        assert_eq!(fs::metadata(&dir).expect("dir").permissions().mode() & 0o777, 0o750);
        std::os::unix::fs::symlink(&dir, &link).expect("symlink");
        assert!(create_private_dir(&link).is_err(), "a symlink is never used");
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn short_host_has_no_domain() {
        if let Some(host) = short_host() {
            assert!(!host.contains('.') && !host.is_empty());
        }
    }
}
