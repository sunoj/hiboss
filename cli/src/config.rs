// Purpose: Load and persist v2 hiboss CLI configuration, migrating v1 once.
// Exports: Config, Profile, config_path, load_config, parse_config, save_config.
// Dependencies: dirs, serde, serde_json, std::fs, std::path::PathBuf.

mod locking;
mod resolve;
mod storage;
use dirs::config_dir;
pub use locking::ConfigLock;
pub use resolve::{Credential, ProfileError, active_profile_name, resolve_credentials};
pub use storage::write_private;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
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
#[serde(deny_unknown_fields)]
pub struct Profile {
    pub key: Option<String>,
    pub agent_id: Option<String>,
    pub name: Option<String>,
    pub server: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub version: u8,
    pub server: Option<String>,
    pub device_id: Option<String>,
    #[serde(default)]
    pub default_profile: String,
    #[serde(skip)]
    pub key: Option<String>,
    pub channel: Option<String>,
    pub profiles: BTreeMap<String, Profile>,
    #[serde(skip)]
    pub selected_profile: Option<String>,
    #[serde(skip)]
    pub original_server: Option<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            version: 2,
            server: None,
            device_id: None,
            default_profile: "default".into(),
            key: None,
            channel: None,
            profiles: BTreeMap::new(),
            selected_profile: None,
            original_server: None,
        }
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyConfig {
    server: Option<String>,
    key: Option<String>,
    channel: Option<String>,
}

pub fn config_path() -> PathBuf {
    if let Some(path) = std::env::var_os("HIBOSS_CONFIG") {
        return PathBuf::from(path);
    }
    config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("hiboss")
        .join("config.json")
}

pub fn load_config() -> Result<Config, Box<dyn Error>> {
    // Rule 1 is intentionally checked before even stat-ing the config path.
    if let Some(credential) = resolve::environment_credential()? {
        return Ok(Config {
            server: Some(credential.server),
            key: Some(credential.key),
            selected_profile: Some(credential.profile),
            ..Config::default()
        });
    }
    let mut config = load_saved_config()?;
    config.select_profile()?;
    config.original_server = config.server.clone();
    Ok(config)
}

/// Load persisted profiles without selecting a runtime or ephemeral credential.
/// Onboarding needs this when the requested runtime has no profile yet.
pub fn load_saved_config() -> Result<Config, Box<dyn Error>> {
    read_saved_config(true)
}

fn read_saved_config(persist_migration: bool) -> Result<Config, Box<dyn Error>> {
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
    if body.trim().is_empty() {
        return Ok(Config::default());
    }
    let value: serde_json::Value = serde_json::from_str(&body)
        .map_err(|err| invalid_config(&path, err.line(), err.column()))?;
    if value.is_object() && value.get("version").is_none() {
        rewrite_legacy(value, &path, persist_migration)
    } else {
        parse_config(&body, &path)
    }
}

fn rewrite_legacy(
    value: serde_json::Value,
    path: &std::path::Path,
    persist: bool,
) -> Result<Config, Box<dyn Error>> {
    let legacy: LegacyConfig =
        serde_json::from_value(value).map_err(|_| invalid_config(path, 1, 1))?;
    let mut migrated = Config {
        server: legacy.server,
        channel: legacy.channel,
        ..Config::default()
    };
    migrated.profiles.insert(
        "default".into(),
        Profile {
            key: legacy.key,
            ..Profile::default()
        },
    );
    if persist {
        save_config(&migrated)?;
    }
    Ok(migrated)
}

/// Parse a config body; a malformed file names itself and one recovery step.
pub fn parse_config(body: &str, path: &std::path::Path) -> Result<Config, Box<dyn Error>> {
    if body.trim().is_empty() {
        return Ok(Config::default());
    }
    let parsed: Config =
        serde_json::from_str(body).map_err(|err| invalid_config(path, err.line(), err.column()))?;
    if parsed.version != 2 {
        return Err(invalid_config(path, 1, 1).into());
    }
    Ok(parsed)
}

fn invalid_config(path: &std::path::Path, line: usize, column: usize) -> LoadError {
    // Serde errors may quote secret values. Report only the position.
    LoadError(format!(
        "config file {} is not valid hiboss configuration (line {line}, column {column}); \
         move the file aside as a backup, then run `hiboss setup --server <server-url>`",
        path.display()
    ))
}

pub fn save_config(config: &Config) -> Result<(), Box<dyn Error>> {
    if resolve::environment_credential()?.is_some() {
        return Err(
            "rule 1: environment credentials are ephemeral; no config file was written".into(),
        );
    }
    let path = config_path();
    let _lock = ConfigLock::acquire(&path)?;
    let mut stored = stored_config(config);
    // Retain profiles added since this command loaded its config snapshot.
    preserve_concurrent_credentials(config, &mut stored, read_saved_config(false)?);
    storage::write_config(&stored, &path)
}

fn preserve_concurrent_credentials(original: &Config, stored: &mut Config, latest: Config) {
    stored.device_id = latest.device_id.or(stored.device_id.take());
    for (name, profile) in latest.profiles {
        if let Some(proposed) = stored.profiles.get_mut(&name) {
            if original
                .profiles
                .get(&name)
                .and_then(|entry| entry.key.as_ref())
                == proposed.key.as_ref()
            {
                proposed.key = profile.key;
                proposed.agent_id = profile.agent_id;
                proposed.name = profile.name;
            }
        } else {
            stored.profiles.insert(name, profile);
        }
    }
    if !stored.profiles.contains_key(&stored.default_profile) {
        stored.default_profile = latest.default_profile;
    }
}

/// Apply an update while holding the same lock used by all config writers.
pub fn update_saved_config(
    update: impl FnOnce(&mut Config) -> Result<(), Box<dyn Error>>,
) -> Result<(), Box<dyn Error>> {
    if resolve::environment_credential()?.is_some() {
        return Err("Environment credentials are ephemeral; no config file was written".into());
    }
    let path = config_path();
    let _lock = ConfigLock::acquire(&path)?;
    let mut config = read_saved_config(false)?;
    update(&mut config)?;
    storage::write_config(&stored_config(&config), &path)
}

fn stored_config(config: &Config) -> Config {
    let mut stored = config.clone();
    stored.version = 2;
    if let Some(name) = config
        .selected_profile
        .as_ref()
        .filter(|name| config.profiles.contains_key(*name))
    {
        let profile = stored.profiles.entry(name.clone()).or_default();
        if config.key != profile.key {
            profile.key.clone_from(&config.key);
        }
        if config.server != config.original_server {
            profile.server.clone_from(&config.server);
            stored.server.clone_from(&config.original_server);
        }
    } else if config.key.is_some() {
        stored
            .profiles
            .entry(stored.default_profile.clone())
            .or_default()
            .key
            .clone_from(&config.key);
    }
    stored.key = None;
    stored.selected_profile = None;
    stored
}

impl Config {
    pub fn require_server(&self) -> Result<String, Box<dyn Error>> {
        Ok(resolve_credentials(self)?.server)
    }

    pub fn require_key(&self) -> Result<String, Box<dyn Error>> {
        Ok(resolve_credentials(self)?.key)
    }
}
