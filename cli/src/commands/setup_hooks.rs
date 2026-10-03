// Purpose: Claude Code hooks configuration for hiboss CLI.
// Exports: SetupHooksArgs, run_setup_hooks.
// Dependencies: clap, serde_json, std::env, std::fs, std::io, std::path.

use clap::Args;
use serde_json::{Map, Value};
use std::env;
use std::error::Error;
use std::fs;
use std::path::PathBuf;

const EVENT_COMMANDS: &[(&str, &str)] = &[
    ("SessionStart", "session-start"),
    ("PostToolUse", "post-tool-use"),
    ("Stop", "stop"),
];

use super::setup_agents::apply_prompt_changes;

#[derive(Debug, Args)]
pub struct SetupHooksArgs {
    #[arg(long, help = "Project directory (default: current dir)")]
    pub dir: Option<String>,
    #[arg(long, help = "Install globally in CLAUDE_CONFIG_DIR or ~/.claude")]
    pub global: bool,
    #[arg(long, help = "Remove hiboss hooks instead of adding")]
    pub remove: bool,
}

pub fn run_setup_hooks(args: &SetupHooksArgs) -> Result<(), Box<dyn Error>> {
    let (claude_dir, label) = hook_destination(args)?;
    eprintln!("[hiboss]Target: {}", label);
    let settings_path = claude_dir.join(if args.global {
        "settings.json"
    } else {
        "settings.local.json"
    });
    let mut settings = read_settings(&settings_path)?;
    eprintln!("[hiboss]Loaded settings from {}", settings_path.display());
    let project_dir = if !args.global && !args.remove {
        Some(project_directory(args)?)
    } else {
        None
    };
    let project_dir_str = project_dir.as_ref().map(|dir| dir.to_string_lossy());
    let change = apply_hook_changes(&mut settings, args.remove, project_dir_str.as_deref())?;
    eprintln!("[hiboss]Computed hook updates");
    if change.changed {
        fs::create_dir_all(&claude_dir)?;
        let serialized = serde_json::to_string_pretty(&settings)?;
        fs::write(&settings_path, format!("{}\n", serialized))?;
        eprintln!("[hiboss]Wrote {}", settings_path.display());
    } else {
        eprintln!("[hiboss]No settings changes required");
    }
    match change.action {
        HookAction::Added => println!("Added or refreshed hiboss hooks in .claude/settings"),
        HookAction::Removed => println!("Removed hiboss hooks from .claude/settings"),
        HookAction::None => println!("hiboss hooks already configured in .claude/settings"),
    }
    apply_prompt_changes(&claude_dir.join("CLAUDE.md"), args.remove)?;
    Ok(())
}

fn hook_destination(args: &SetupHooksArgs) -> Result<(PathBuf, String), Box<dyn Error>> {
    let (claude_dir, label) = if args.global {
        let path = match env::var_os("CLAUDE_CONFIG_DIR").filter(|value| !value.is_empty()) {
            Some(path) => PathBuf::from(path),
            None => PathBuf::from(env::var("HOME").map_err(|_| "HOME not set")?).join(".claude"),
        };
        let label = format!("global {}", path.display());
        (path, label)
    } else {
        let project_dir = project_directory(args)?;
        (
            project_dir.join(".claude"),
            format!("{}", project_dir.display()),
        )
    };
    Ok((claude_dir, label))
}

fn project_directory(args: &SetupHooksArgs) -> Result<PathBuf, Box<dyn Error>> {
    Ok(match &args.dir {
        Some(dir) => PathBuf::from(dir),
        None => env::current_dir()?,
    })
}

fn read_settings(settings_path: &std::path::Path) -> Result<Value, Box<dyn Error>> {
    if settings_path.exists() {
        let contents = fs::read_to_string(settings_path)?;
        let parsed = serde_json::from_str::<Value>(&contents)?;
        match parsed {
            Value::Object(_) => Ok(parsed),
            _ => Err("settings.json must contain an object".into()),
        }
    } else {
        Ok(Value::Object(Map::new()))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HookAction {
    Added,
    Removed,
    None,
}

#[derive(Debug)]
struct HookChange {
    changed: bool,
    action: HookAction,
}

impl Default for HookChange {
    fn default() -> Self {
        Self {
            changed: false,
            action: HookAction::None,
        }
    }
}

fn apply_hook_changes(
    settings: &mut Value,
    remove: bool,
    project_dir: Option<&str>,
) -> Result<HookChange, Box<dyn Error>> {
    let root = settings
        .as_object_mut()
        .ok_or("settings.json must contain an object")?;

    if remove {
        return remove_hook_changes(root);
    }

    let hooks_value = root
        .entry("hooks")
        .or_insert_with(|| Value::Object(Map::new()));
    let hooks_map = hooks_value
        .as_object_mut()
        .ok_or("hooks must be an object")?;
    let mut change = HookChange::default();
    for event_value in hooks_map.values_mut() {
        change.changed |= refresh_managed_hooks(event_value, project_dir)?;
    }
    for (event, command_label) in EVENT_COMMANDS {
        let entry = hooks_map
            .entry(event.to_string())
            .or_insert_with(|| Value::Array(vec![]));
        let arr = entry
            .as_array_mut()
            .ok_or_else(|| format!("hooks.{} must be an array", event))?;
        if arr.iter().any(matcher_contains_hiboss) {
            continue;
        }
        arr.push(new_hiboss_matcher(command_label, project_dir));
        change.changed = true;
    }
    if change.changed {
        change.action = HookAction::Added;
    }
    Ok(change)
}

fn remove_hook_changes(root: &mut Map<String, Value>) -> Result<HookChange, Box<dyn Error>> {
    let Some(hooks_value) = root.get_mut("hooks") else {
        return Ok(HookChange::default());
    };
    let hooks_map = hooks_value
        .as_object_mut()
        .ok_or("hooks must be an object")?;
    let mut change = HookChange::default();
    for (event, value) in hooks_map.iter_mut() {
        let matchers = value
            .as_array_mut()
            .ok_or_else(|| format!("hooks.{event} must be an array"))?;
        for matcher in matchers.iter_mut() {
            if let Some(hooks) = matcher.get_mut("hooks").and_then(Value::as_array_mut) {
                let original = hooks.len();
                hooks.retain(|hook| !is_hiboss_hook(hook));
                change.changed |= original != hooks.len();
            }
        }
        matchers.retain(|matcher| {
            !matcher
                .get("hooks")
                .and_then(Value::as_array)
                .is_some_and(Vec::is_empty)
        });
    }
    hooks_map.retain(|_, value| !value.as_array().is_some_and(Vec::is_empty));
    if hooks_map.is_empty() {
        root.remove("hooks");
    }
    if change.changed {
        change.action = HookAction::Removed;
    }
    Ok(change)
}

fn is_hiboss_hook(value: &Value) -> bool {
    value
        .get("command")
        .and_then(Value::as_str)
        .is_some_and(|command| command.contains("hiboss hook "))
}

fn refresh_managed_hooks(
    value: &mut Value,
    project_dir: Option<&str>,
) -> Result<bool, Box<dyn Error>> {
    let matchers = value.as_array_mut().ok_or("hook event must be an array")?;
    let mut changed = false;
    for matcher in matchers {
        if let Some(hooks) = matcher.get_mut("hooks").and_then(Value::as_array_mut) {
            for hook in hooks.iter_mut().filter(|hook| is_hiboss_hook(hook)) {
                let old = hook["command"]
                    .as_str()
                    .ok_or("hook command must be a string")?;
                let (_, invocation) = old
                    .split_once("hiboss hook ")
                    .ok_or("invalid HiBoss hook")?;
                let command = profile_hook_command(invocation, project_dir);
                if old != command {
                    hook["command"] = Value::String(command);
                    changed = true;
                }
            }
        }
    }
    Ok(changed)
}

fn matcher_contains_hiboss(value: &Value) -> bool {
    value
        .get("hooks")
        .and_then(Value::as_array)
        .map(|hooks| hooks.iter().any(is_hiboss_hook))
        .unwrap_or(false)
}

fn new_hiboss_matcher(command_label: &str, project_dir: Option<&str>) -> Value {
    let command = profile_hook_command(command_label, project_dir);
    let mut hook_obj = Map::new();
    hook_obj.insert("type".to_string(), Value::String("command".to_string()));
    hook_obj.insert("command".to_string(), Value::String(command));
    let mut matcher_obj = Map::new();
    matcher_obj.insert("matcher".to_string(), Value::String(String::new()));
    matcher_obj.insert(
        "hooks".to_string(),
        Value::Array(vec![Value::Object(hook_obj)]),
    );
    Value::Object(matcher_obj)
}

fn profile_hook_command(command_label: &str, project_dir: Option<&str>) -> String {
    let command = if let Some(dir) = project_dir {
        format!(
            "HIBOSS_PROFILE=claude HIBOSS_PROJECT_DIR={} hiboss hook {}",
            shell_escape(dir),
            command_label
        )
    } else {
        format!("HIBOSS_PROFILE=claude hiboss hook {}", command_label)
    };
    command
}

fn shell_escape(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

#[cfg(test)]
#[path = "../tests/setup.rs"]
mod tests;
