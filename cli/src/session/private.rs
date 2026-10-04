// Owner-only file I/O inside the session state directory; foreign or exposed files are refused.
// Exports state_file, read_state, write_state, append_state, open_log, remove_state, take_state.
// Dependencies: state::state_dir, std::fs, libc (unix).

use super::state::state_dir;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

static REFUSED: Mutex<Vec<PathBuf>> = Mutex::new(Vec::new());

/// One file in this session's state directory; None when the directory failed validation.
pub fn state_file(name: &str) -> Option<PathBuf> {
    state_dir().map(|dir| dir.join(name))
}

/// Contents of a state file, or None if it is missing, unsafe, or the directory is unusable.
pub fn read_state(name: &str) -> Option<String> {
    read_private(&state_file(name)?)
}

/// Replace a state file's contents, creating it 0600.
pub fn write_state(name: &str, content: &str) -> io::Result<()> {
    let file = open_private(&path_for(name)?, OpenOptions::new().write(true).create(true))?;
    file.set_len(0)?;
    (&file).write_all(content.as_bytes())
}

/// Append to a state file, creating it 0600.
pub fn append_state(name: &str, content: &str) -> io::Result<()> {
    let mut options = OpenOptions::new();
    options.append(true).create(true);
    (&open_private(&path_for(name)?, &mut options)?).write_all(content.as_bytes())
}

/// A truncated, owner-only log file in the state directory.
pub fn open_log(name: &str) -> io::Result<File> {
    let file = open_private(&path_for(name)?, OpenOptions::new().write(true).create(true))?;
    file.set_len(0)?;
    Ok(file)
}

/// Delete a state file; a missing file or unusable directory is not an error.
pub fn remove_state(name: &str) {
    if let Some(path) = state_file(name) {
        let _ = fs::remove_file(path);
    }
}

/// Atomically take a state file's contents, leaving it absent. The rename moves the inode,
/// so the ownership check after it applies to exactly the bytes that are read.
pub fn take_state(name: &str) -> Option<String> {
    let path = state_file(name)?;
    let draining = path.with_extension("draining");
    fs::rename(&path, &draining).ok()?;
    let content = read_private(&draining);
    let _ = fs::remove_file(&draining);
    content
}

fn path_for(name: &str) -> io::Result<PathBuf> {
    state_file(name).ok_or_else(|| io::Error::other("session state directory is unusable"))
}

fn read_private(path: &Path) -> Option<String> {
    let file = open_private(path, OpenOptions::new().read(true)).ok()?;
    let mut content = String::new();
    (&file).read_to_string(&mut content).ok()?;
    Some(content)
}

/// Open without following a final symlink or blocking on a FIFO, then refuse anything but a
/// regular 0600 file owned by the caller. Nothing is truncated before that check passes.
fn open_private(path: &Path, options: &mut OpenOptions) -> io::Result<File> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600).custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
    }
    let checked = options.open(path).and_then(|file| {
        check_private(&file.metadata()?)?;
        Ok(file)
    });
    if let Err(err) = &checked {
        if err.kind() != io::ErrorKind::NotFound {
            refuse(path, err);
        }
    }
    checked
}

#[cfg(unix)]
fn check_private(meta: &fs::Metadata) -> io::Result<()> {
    use std::os::unix::fs::MetadataExt;
    let euid = unsafe { libc::geteuid() };
    if meta.file_type().is_file() && meta.uid() == euid && meta.mode() & 0o777 == 0o600 {
        return Ok(());
    }
    Err(io::Error::new(
        io::ErrorKind::PermissionDenied,
        "not a regular 0600 file owned by the current user",
    ))
}

#[cfg(not(unix))]
fn check_private(meta: &fs::Metadata) -> io::Result<()> {
    match meta.is_file() {
        true => Ok(()),
        false => Err(io::Error::other("not a regular file")),
    }
}

/// One warning per refused path and process.
fn refuse(path: &Path, err: &io::Error) {
    let Ok(mut refused) = REFUSED.lock() else { return };
    if refused.iter().any(|seen| seen == path) {
        return;
    }
    refused.push(path.to_owned());
    eprintln!("hiboss: refusing session state file {}: {err}", path.display());
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hiboss-private-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("scratch dir");
        dir
    }

    #[test]
    fn refuses_exposed_files_without_truncating_them() {
        let dir = scratch("exposed");
        let path = dir.join("session");
        fs::write(&path, "planted").expect("plant");
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).expect("chmod");
        assert_eq!(read_private(&path), None);
        assert!(open_private(&path, OpenOptions::new().write(true)).is_err());
        assert_eq!(fs::read_to_string(&path).expect("still there"), "planted");
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn refuses_symlinks_and_reads_private_files() {
        let dir = scratch("link");
        let target = dir.join("target");
        fs::write(&target, "x").expect("target");
        fs::set_permissions(&target, fs::Permissions::from_mode(0o600)).expect("chmod");
        assert_eq!(read_private(&target).as_deref(), Some("x"));
        let link = dir.join("link");
        std::os::unix::fs::symlink(&target, &link).expect("symlink");
        assert_eq!(read_private(&link), None);
        let _ = fs::remove_dir_all(dir);
    }
}
