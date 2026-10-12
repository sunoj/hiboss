// Discovers Claude configuration profiles and checks their lifecycle hooks.
// Exports shared profile paths, process detection, repair commands, and diagnostics.
// Dependencies: environment, filesystem, serde_json, setup_hooks.

use serde_json::Value;
use std::{
    env,
    error::Error,
    fs,
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
};

pub(super) fn current() -> Result<PathBuf, Box<dyn Error>> {
    if let Some(path) = env::var_os("CLAUDE_CONFIG_DIR").filter(|value| !value.is_empty()) {
        return absolute(Path::new(&path));
    }
    absolute(&home()?.join(".claude"))
}

fn home() -> Result<PathBuf, Box<dyn Error>> {
    absolute(Path::new(&env::var_os("HOME").ok_or("HOME not set")?))
}

pub(super) fn absolute(path: &Path) -> Result<PathBuf, Box<dyn Error>> {
    let expanded = match path.strip_prefix("~") {
        Ok(rest) => PathBuf::from(env::var_os("HOME").ok_or("HOME not set")?).join(rest),
        Err(_) => path.to_owned(),
    };
    let absolute = if expanded.is_absolute() {
        expanded
    } else {
        env::current_dir()?.join(expanded)
    };
    Ok(fs::canonicalize(&absolute).unwrap_or(absolute))
}

pub(super) fn discover() -> Result<Vec<PathBuf>, Box<dyn Error>> {
    let home = home()?;
    // The current profile always counts; ~/.claude joins it only when it already exists.
    let mut paths = vec![current()?];
    if home.join(".claude").is_dir() {
        paths.push(absolute(&home.join(".claude"))?);
    }
    if home.is_dir() {
        for entry in fs::read_dir(&home)? {
            let entry = entry?;
            let path = entry.path();
            if !entry.file_name().to_string_lossy().starts_with(".claude-") {
                continue;
            }
            let metadata = fs::symlink_metadata(&path)?;
            if metadata.file_type().is_symlink() {
                println!("Claude profile {}: skipped (symlink)", path.display());
                continue;
            }
            if metadata.is_dir() && path.join("projects").is_dir() {
                paths.push(absolute(&path)?);
            }
        }
    }
    paths.sort();
    paths.dedup();
    Ok(paths)
}

pub(super) fn inside_claude() -> bool {
    env::var("CLAUDECODE").is_ok_and(|value| value == "1")
        || env::var_os("CLAUDE_CODE_ENTRYPOINT").is_some_and(|value| !value.is_empty())
}

pub(super) fn fix_command(path: &Path) -> String {
    let escaped = path.to_string_lossy().replace('\'', "'\\''");
    format!("hiboss setup hooks --global --config-dir '{escaped}'")
}

pub(super) fn installed(path: &Path) -> bool {
    let Ok(raw) = fs::read_to_string(path.join("settings.json")) else {
        return false;
    };
    let Ok(settings) = serde_json::from_str::<Value>(&raw) else {
        return false;
    };
    super::setup_hooks::hooks_installed(&settings)
}

pub(super) fn doctor() -> Result<bool, Box<dyn Error>> {
    let current = current()?;
    let mut missing_current = false;
    for path in discover()? {
        let installed = installed(&path);
        println!(
            "Claude profile {}: hooks {}",
            path.display(),
            if installed { "installed" } else { "missing" }
        );
        if !installed {
            println!("  Fix: {}", fix_command(&path));
            missing_current |= path == current && inside_claude();
        }
    }
    Ok(missing_current)
}

static WARNED: AtomicBool = AtomicBool::new(false);

pub(super) fn warn_missing_session(session_id: Option<&str>) {
    if session_id.is_some() || !inside_claude() {
        return;
    }
    let Ok(profile) = current() else {
        return;
    };
    if let Some(warning) = session_warning(&profile, &WARNED) {
        eprintln!("{warning}");
    }
}

fn session_warning(profile: &Path, warned: &AtomicBool) -> Option<String> {
    if warned.swap(true, Ordering::Relaxed) {
        return None;
    }
    Some(format!(
        concat!(
            "Warning: no HiBoss session registered for Claude profile {}; ",
            "messages will appear as direct messages. Fix: {}"
        ),
        profile.display(),
        fix_command(profile)
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn send_warning_is_emitted_once_and_quotes_the_profile() {
        let warned = AtomicBool::new(false);
        let profile = Path::new("/tmp/Claude's profile");
        let first = session_warning(profile, &warned).expect("first warning");
        assert!(first.contains("messages will appear as direct messages"));
        assert!(first.contains("--config-dir '/tmp/Claude'\\''s profile'"));
        assert!(session_warning(profile, &warned).is_none());
    }
}
