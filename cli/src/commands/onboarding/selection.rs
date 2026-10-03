// Resolves a machine's server, runtime profiles, hostname, and valid agent names.
// Exports Plan, build_plan, sanitize_name, and server normalization within onboarding.
// Dependencies: persisted Config, setup args, and executable PATH inspection.

use super::{SetupArgs, api::RequestedProfile};
use crate::config::Config;
use std::{collections::BTreeSet, error::Error, path::Path, process::Command};

pub(super) struct Plan {
    pub server: String,
    pub label: String,
    pub host: String,
    pub profiles: Vec<RequestedProfile>,
    pub proof: Option<String>,
}

pub(crate) fn normalize_server(server: &str) -> Result<String, Box<dyn Error>> {
    let url = reqwest::Url::parse(server).map_err(|_| "Invalid --server URL")?;
    if !matches!(url.scheme(), "http" | "https")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(
            "--server must be an HTTP(S) URL without credentials, query or fragment".into(),
        );
    }
    Ok(url.as_str().trim_end_matches('/').to_owned())
}

pub(super) fn build_plan(args: &SetupArgs, config: &Config) -> Result<Plan, Box<dyn Error>> {
    let server = normalize_server(
        args.server
            .as_deref()
            .or(config.server.as_deref())
            .ok_or("Server is not configured; pass --server <url> to hiboss setup")?,
    )?;
    if let Some(existing) = config.server.as_deref() {
        if normalize_server(existing)? != server && !config.profiles.is_empty() {
            return Err(
                "Existing profiles belong to another server; use a separate HIBOSS_CONFIG".into(),
            );
        }
    }
    let host = hostname();
    let label = args
        .label
        .clone()
        .unwrap_or_else(|| host.split('.').next().unwrap_or("machine").into());
    if label.is_empty() || label.chars().count() > 64 || label.chars().any(char::is_control) {
        return Err("--label must be 1–64 printable characters".into());
    }
    let profiles = requested_profiles(args, config, &label)?;
    let proof = config.device_id.as_ref().and_then(|_| {
        config
            .profiles
            .values()
            .find(|profile| {
                profile
                    .server
                    .as_deref()
                    .map(|url| url.trim_end_matches('/') == server)
                    .unwrap_or(true)
                    && profile.key.as_ref().is_some_and(|key| !key.is_empty())
            })
            .and_then(|profile| profile.key.clone())
    });
    Ok(Plan {
        server,
        host,
        label,
        profiles,
        proof,
    })
}

fn requested_profiles(
    args: &SetupArgs,
    config: &Config,
    label: &str,
) -> Result<Vec<RequestedProfile>, Box<dyn Error>> {
    let candidates = if args.profile.is_empty() {
        ["claude", "codex", "gemini", "aid"]
            .into_iter()
            .filter(|name| on_path(name))
            .map(String::from)
            .collect()
    } else {
        args.profile.clone()
    };
    let unique: BTreeSet<String> = candidates.into_iter().collect();
    if unique.len() > 8 {
        return Err("At most 8 profiles may be requested".into());
    }
    let user = std::env::var("USER").unwrap_or_else(|_| "user".into());
    let mut profiles = Vec::new();
    for profile in unique {
        if !valid_profile(&profile) {
            return Err("Profile must match ^[a-z][a-z0-9-]{0,31}$".into());
        }
        if config.profiles.contains_key(&profile) {
            println!("Skipping profile {profile}: already configured");
        } else {
            let name = sanitize_name(&format!("{user}-{profile}@{label}"));
            profiles.push(RequestedProfile { profile, name });
        }
    }
    Ok(profiles)
}

pub(super) fn valid_profile(profile: &str) -> bool {
    !profile.is_empty()
        && profile.len() <= 32
        && profile.as_bytes()[0].is_ascii_lowercase()
        && profile
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
}

pub(super) fn sanitize_name(input: &str) -> String {
    let cleaned: String = input
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || "._@+-".contains(c) {
                c
            } else {
                '-'
            }
        })
        .collect();
    let trimmed = cleaned.trim_start_matches(|c: char| !c.is_ascii_alphanumeric());
    if trimmed.is_empty() {
        "user".into()
    } else {
        trimmed.chars().take(100).collect()
    }
}

fn hostname() -> String {
    Command::new("hostname")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|name| name.trim().to_owned())
        .filter(|name| !name.is_empty())
        .or_else(|| std::env::var("HOSTNAME").ok())
        .unwrap_or_else(|| "machine".into())
}

fn on_path(name: &str) -> bool {
    std::env::var_os("PATH")
        .is_some_and(|path| std::env::split_paths(&path).any(|dir| executable(&dir.join(name))))
}

fn executable(path: &Path) -> bool {
    let Ok(metadata) = path.metadata() else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sanitization_obeys_name_contract() {
        assert_eq!(
            sanitize_name(" 王 Alice-claude@My Mac!"),
            "Alice-claude@My-Mac-"
        );
        assert_eq!(sanitize_name("..."), "user");
        assert_eq!(sanitize_name(&"a".repeat(120)).len(), 100);
        assert!(valid_profile("claude-2"));
        assert!(!valid_profile("Codex"));
    }
}
