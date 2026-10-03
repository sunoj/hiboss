// Purpose: Select one credential profile without performing config persistence.
// Exports: Credential, ProfileError, resolve_credentials.
// Dependencies: Config, RuntimeIdentity, std::env.

use super::{Config, config_path};
use crate::runtime::RuntimeIdentity;
use std::error::Error;
use std::fmt;

#[derive(Clone, Debug)]
pub struct Credential {
    pub profile: String,
    pub source_rule: u8,
    pub name: Option<String>,
    pub server: String,
    pub key: String,
    pub runtime: RuntimeIdentity,
}

#[derive(Debug)]
pub struct ProfileError(pub String);

impl fmt::Display for ProfileError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}
impl Error for ProfileError {}

fn env_value(name: &str) -> Option<String> {
    std::env::var(name)
        .ok()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.trim().is_empty())
}

pub(super) fn environment_credential() -> Result<Option<Credential>, Box<dyn Error>> {
    let server = env_value("HIBOSS_SERVER");
    let key = env_value("HIBOSS_KEY");
    let runtime = RuntimeIdentity::detect();
    match (server, key) {
        (Some(server), Some(key)) => Ok(Some(Credential {
            profile: "environment".into(),
            source_rule: 1,
            name: None,
            server,
            key,
            runtime,
        })),
        (Some(_), None) => Err(
            "rule 1: HIBOSS_KEY is missing; HIBOSS_SERVER and HIBOSS_KEY must be set together"
                .into(),
        ),
        (None, Some(_)) => Err(
            "rule 1: HIBOSS_SERVER is missing; HIBOSS_SERVER and HIBOSS_KEY must be set together"
                .into(),
        ),
        (None, None)
            if std::env::var_os("HIBOSS_SERVER").is_some()
                || std::env::var_os("HIBOSS_KEY").is_some() =>
        {
            Err("rule 1: HIBOSS_SERVER and HIBOSS_KEY are missing; set both together".into())
        }
        (None, None) => Ok(None),
    }
}

fn selected(config: &Config, runtime: &RuntimeIdentity) -> Result<(String, u8), ProfileError> {
    if std::env::var_os("HIBOSS_PROFILE").is_some() && env_value("HIBOSS_PROFILE").is_none() {
        return Err(ProfileError(
            "rule 2: HIBOSS_PROFILE is empty; choose a configured profile".into(),
        ));
    }
    if let Some(name) = env_value("HIBOSS_PROFILE") {
        if !config.profiles.contains_key(&name) {
            return Err(ProfileError(format!(
                "rule 2: profile '{name}' is not set up; run: hiboss setup --profile {name}"
            )));
        }
        return Ok((name, 2));
    }
    if runtime.runtime != "none" && config.profiles.contains_key(&runtime.runtime) {
        return Ok((runtime.runtime.clone(), 3));
    }
    Ok((config.default_profile.clone(), 4))
}

pub fn resolve_credentials(config: &Config) -> Result<Credential, Box<dyn Error>> {
    if let Some(credential) = environment_credential()? {
        return Ok(credential);
    }
    let runtime = RuntimeIdentity::detect();
    let (profile_name, source_rule) = selected(config, &runtime)?;
    let profile = config.profiles.get(&profile_name);
    let server = profile.and_then(|entry| present(&entry.server))
        .or_else(|| present(&config.server))
        .ok_or_else(|| format!("rule {source_rule}: server is not configured in {}; run `hiboss config set server <url>`", config_path().display()))?;
    let key = profile.and_then(|entry| present(&entry.key))
        .ok_or_else(|| format!("rule {source_rule}: API key is missing for profile '{profile_name}' in {}; run `hiboss init <server-url>` or `hiboss setup --profile {profile_name}`", config_path().display()))?;
    Ok(Credential {
        profile: profile_name,
        source_rule,
        name: profile.and_then(|entry| entry.name.clone()),
        server,
        key,
        runtime,
    })
}

fn present(value: &Option<String>) -> Option<String> {
    value.clone().filter(|found| !found.trim().is_empty())
}

impl Config {
    pub fn select_profile(&mut self) -> Result<(), ProfileError> {
        let (name, _) = selected(self, &RuntimeIdentity::detect())?;
        self.key = self
            .profiles
            .get(&name)
            .and_then(|profile| profile.key.clone());
        self.selected_profile = Some(name);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn default_profile_requires_server_then_key_with_rule() {
        let mut config = Config::default();
        assert!(
            resolve_credentials(&config)
                .unwrap_err()
                .to_string()
                .contains("rule 4: server")
        );
        config.server = Some("https://example.test".into());
        assert!(
            resolve_credentials(&config)
                .unwrap_err()
                .to_string()
                .contains("rule 4: API key")
        );
    }

    #[test]
    fn selected_profile_facade_reads_profile_key() {
        let mut config = Config {
            server: Some("https://example.test".into()),
            ..Config::default()
        };
        config.profiles.insert(
            "default".into(),
            super::super::Profile {
                key: Some("secret".into()),
                ..Default::default()
            },
        );
        config.select_profile().unwrap();
        assert_eq!(config.key.as_deref(), Some("secret"));
        assert_eq!(resolve_credentials(&config).unwrap().source_rule, 4);
    }
}
