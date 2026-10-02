// Purpose: Load, persist, and validate hiboss CLI configuration values.
// Exports: Config, config_path, load_config, parse_config, save_config, require_server, require_key.
// Dependencies: dirs, serde, serde_json, std::fs, std::path::PathBuf.

use dirs::config_dir;
use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fmt;
use std::fs;
use std::path::PathBuf;

/// Configuration loading failed before command execution; retain exit status 1.
#[derive(Debug)]
pub struct LoadError(String);

impl fmt::Display for LoadError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl Error for LoadError {}

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
    let body = fs::read_to_string(&path).map_err(|err| {
        LoadError(format!(
            "cannot read config file {} ({err}); check the file's read permissions",
            path.display()
        ))
    })?;
    parse_config(&body, &path)
}

/// Parse a config body; a malformed file names itself and one recovery step.
pub fn parse_config(body: &str, path: &std::path::Path) -> Result<Config, Box<dyn Error>> {
    if body.trim().is_empty() {
        return Ok(Config::default());
    }
    serde_json::from_str(body).map_err(|err| {
        // Report only the position: serde messages can quote values such as the key.
        let shown = path.display();
        LoadError(format!(
            "config file {shown} is not valid hiboss configuration (line {}, column {}); \
             move the file aside as a backup, then run `hiboss init <server-url>`",
            err.line(),
            err.column()
        ))
        .into()
    })
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
        if let Some(server) = present(&self.server) {
            return Ok(server);
        }
        let step = if present(&self.key).is_some() {
            "run `hiboss config set server <url>`"
        } else {
            "run `hiboss init <server-url>` to join a server"
        };
        Err(format!(
            "server is not configured in {}; {step}",
            config_path().display()
        )
        .into())
    }

    pub fn require_key(&self) -> Result<String, Box<dyn Error>> {
        if let Some(key) = present(&self.key) {
            return Ok(key);
        }
        Err(format!(
            "API key is missing in {}; run `hiboss init <server-url>` with your configured server to request one",
            config_path().display()
        )
        .into())
    }
}

/// A configured value counts only when it is non-blank.
fn present(value: &Option<String>) -> Option<String> {
    value.clone().filter(|found| !found.trim().is_empty())
}
