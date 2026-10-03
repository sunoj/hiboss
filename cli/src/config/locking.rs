// Serializes config read/merge/rename transactions across local CLI processes.
// Exports ConfigLock; depends on owner-only files and Unix advisory flock.
// Locks release on process exit without leaving a stale lock that blocks updates.

use std::{
    error::Error,
    fs::{self, File, OpenOptions},
    path::Path,
};

pub struct ConfigLock {
    _file: File,
}

impl ConfigLock {
    pub fn acquire(path: &Path) -> Result<Self, Box<dyn Error>> {
        Self::lock(path, "config-lock", false)
    }

    pub fn begin_enrollment(path: &Path) -> Result<Self, Box<dyn Error>> {
        Self::lock(path, "setup-lock", true)
            .map_err(|_| "Another setup is running for this config; wait for it to finish".into())
    }

    fn lock(path: &Path, extension: &str, nonblocking: bool) -> Result<Self, Box<dyn Error>> {
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)?;
        }
        let mut options = OpenOptions::new();
        options.read(true).write(true).create(true);
        #[cfg(unix)]
        {
            use std::os::unix::{fs::OpenOptionsExt, io::AsRawFd};
            options.mode(0o600);
            let file = options.open(path.with_extension(extension))?;
            let operation = libc::LOCK_EX | if nonblocking { libc::LOCK_NB } else { 0 };
            // The fd stays open in this guard; flock neither reads nor writes its contents.
            if unsafe { libc::flock(file.as_raw_fd(), operation) } != 0 {
                return Err(std::io::Error::last_os_error().into());
            }
            Ok(Self { _file: file })
        }
        #[cfg(not(unix))]
        {
            Err("Atomic profile updates require Unix file locking".into())
        }
    }
}
