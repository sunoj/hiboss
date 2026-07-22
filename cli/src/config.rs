// Purpose: Load, persist, and validate hiboss CLI configuration values.
// Exports: Config, config_path, load_config, save_config, require_server, require_key.
// Dependencies: dirs, serde, serde_json, std::fs, std::path::PathBuf.

use dirs::config_dir;
use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fs;
use std::path::PathBuf;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Config {
    pub server: Option<String>,
    pub key: Option<String>,
    pub channel: Option<String>,
}

pub fn config_path() -> PathBuf {
    config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("hiboss")
        .join("config.json")
}

pub fn load_config() -> Result<Config, Box<dyn Error>> {
    let path = config_path();
    if !path.is_file() {
        return Ok(Config::default());
    }
    let body = fs::read_to_string(&path)?;
    if body.trim().is_empty() {
        return Ok(Config::default());
    }
    let config = serde_json::from_str(&body)?;
    Ok(config)
}

pub fn save_config(config: &Config) -> Result<(), Box<dyn Error>> {
    let path = config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
        restrict_permissions(parent, 0o700);
    }
    let payload = serde_json::to_string_pretty(config)?;
    fs::write(&path, payload)?;
    // The config holds the API key in plaintext; keep it owner-only.
    restrict_permissions(&path, 0o600);
    Ok(())
}

/// Best-effort tighten of file/dir permissions on unix; a no-op elsewhere.
fn restrict_permissions(path: &std::path::Path, mode: u32) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(mode));
    }
    #[cfg(not(unix))]
    {
        let _ = (path, mode);
    }
}

impl Config {
    pub fn require_server(&self) -> Result<String, Box<dyn Error>> {
        self.server
            .clone()
            .ok_or_else(|| "server is not configured; run `hiboss config set server <url>`".into())
    }

    pub fn require_key(&self) -> Result<String, Box<dyn Error>> {
        self.key
            .clone()
            .ok_or_else(|| "API key is missing; run `hiboss config set key <value>`".into())
    }
}
