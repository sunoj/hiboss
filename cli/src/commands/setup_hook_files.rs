// Resolves runtime-specific lifecycle settings and project instruction locations.
// Exports destination, project_directory, read_settings; performs no registration.
// Dependencies: environment, filesystem, and JSON objects.

use super::setup_hooks::{SetupHooksArgs, SetupRuntime};
use serde_json::{Map, Value};
use std::{
    env,
    error::Error,
    fs,
    path::{Path, PathBuf},
};

pub(super) fn destination(args: &SetupHooksArgs) -> Result<(PathBuf, String), Box<dyn Error>> {
    let directory = if args.runtime == SetupRuntime::Codex {
        ".codex"
    } else {
        ".claude"
    };
    let variable = if args.runtime == SetupRuntime::Codex {
        "CODEX_HOME"
    } else {
        "CLAUDE_CONFIG_DIR"
    };
    let path = if args.global {
        match env::var_os(variable).filter(|value| !value.is_empty()) {
            Some(path) => PathBuf::from(path),
            None => PathBuf::from(env::var("HOME").map_err(|_| "HOME not set")?).join(directory),
        }
    } else {
        project_directory(args)?.join(directory)
    };
    let label = path.display().to_string();
    Ok((path, label))
}

pub(super) fn project_directory(args: &SetupHooksArgs) -> Result<PathBuf, Box<dyn Error>> {
    Ok(match &args.dir {
        Some(dir) => PathBuf::from(dir),
        None => env::current_dir()?,
    })
}

pub(super) fn read_settings(path: &Path) -> Result<Value, Box<dyn Error>> {
    if !path.exists() {
        return Ok(Value::Object(Map::new()));
    }
    let parsed: Value = serde_json::from_str(&fs::read_to_string(path)?)?;
    match parsed {
        Value::Object(_) => Ok(parsed),
        _ => Err("Lifecycle settings must contain an object".into()),
    }
}

pub(super) fn write_settings(
    path: &Path,
    settings: &Value,
    changed: bool,
) -> Result<(), Box<dyn Error>> {
    if changed {
        let parent = path.parent().ok_or("Missing settings directory")?;
        fs::create_dir_all(parent)?;
        fs::write(
            path,
            format!("{}\n", serde_json::to_string_pretty(settings)?),
        )?;
        eprintln!("[hiboss]Wrote {}", path.display());
    } else {
        eprintln!("[hiboss]No settings changes required");
    }
    Ok(())
}
