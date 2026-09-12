// Durable atomic config swaps with an owner-only previous-key backup.
// Exports RotationConfig; depends only on std filesystem and serde_json.
use std::{error::Error, fs::{self, File, OpenOptions}, io::Write, path::{Path, PathBuf}};

pub struct RotationConfig {
    path: PathBuf, backup: PathBuf, lock: PathBuf, original: Vec<u8>, installed: Option<Vec<u8>>,
}
impl RotationConfig {
    pub fn open(path: &Path, key: &str) -> Result<Self, Box<dyn Error>> {
        let lock = path.with_extension("key-lock");
        private_file(&lock).map_err(|_| "rotation already running or stale .key-lock exists; active config unchanged")?;
        let mut result = Self { path: path.into(), backup: path.with_extension("key-previous"), lock,
            original: Vec::new(), installed: None };
        result.original = fs::read(path)?;
        let value: serde_json::Value = serde_json::from_slice(&result.original)?;
        if value.get("key").and_then(|k| k.as_str()) != Some(key) {
            return Err("config changed; previous active key kept".into());
        }
        let mut backup = private_file(&result.backup)
            .map_err(|_| "previous rotation backup exists; resolve .key-previous before retrying; active config unchanged")?;
        backup.write_all(&result.original)?;
        backup.sync_all()?;
        Ok(result)
    }
    pub fn backup_path(&self) -> &Path { &self.backup }
    pub fn install(&mut self, key: &str) -> Result<(), Box<dyn Error>> {
        if fs::read(&self.path)? != self.original { return Err("config changed during rotation; active config kept".into()); }
        let mut value: serde_json::Value = serde_json::from_slice(&self.original)?;
        value["key"] = key.into();
        let bytes = serde_json::to_vec_pretty(&value)?;
        atomic_write(&self.path, &bytes)?;
        self.installed = Some(bytes);
        Ok(())
    }
    pub fn restore(&mut self) -> Result<(), Box<dyn Error>> {
        if self.installed.as_ref() != Some(&fs::read(&self.path)?) {
            return Err("config changed after rotation; previous key remains in backup".into());
        }
        atomic_write(&self.path, &self.original)?;
        self.installed = None;
        Ok(())
    }
    pub fn finish(&self) -> Result<(), Box<dyn Error>> { fs::remove_file(&self.backup)?; Ok(()) }
}
impl Drop for RotationConfig {
    fn drop(&mut self) { let _ = fs::remove_file(&self.lock); }
}
fn private_file(path: &Path) -> std::io::Result<File> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)] { use std::os::unix::fs::OpenOptionsExt; options.mode(0o600); }
    options.open(path)
}
fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), Box<dyn Error>> {
    let temporary = path.with_extension("key-next");
    let mut file = private_file(&temporary)?;
    let result = (|| -> std::io::Result<()> {
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temporary, path)?;
        Ok(())
    })();
    if result.is_err() { let _ = fs::remove_file(temporary); }
    result?;
    // Best effort directory fsync after rename; never report a pre-swap failure after a swap.
    if let Some(parent) = path.parent() { if let Ok(dir) = File::open(parent) { let _ = dir.sync_all(); } }
    Ok(())
}
