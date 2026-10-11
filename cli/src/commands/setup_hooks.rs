// Purpose: Claude Code hooks configuration for hiboss CLI.
// Exports: SetupHooksArgs, run_setup_hooks.
// Dependencies: clap, serde_json, std::env, std::fs, std::io, std::path.

use clap::{Args, ValueEnum};
use serde_json::{Map, Value};
use std::error::Error;

const EVENT_COMMANDS: &[(&str, &str)] = &[
    ("SessionStart", "session-start"),
    ("PostToolUse", "post-tool-use"),
    ("Stop", "stop"),
];

use super::setup_agents::apply_prompt_changes;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum SetupRuntime {
    Claude,
    Codex,
}

impl SetupRuntime {
    fn profile(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
        }
    }
}

#[derive(Debug, Args)]
pub struct SetupHooksArgs {
    #[arg(long, default_value = "claude")]
    pub runtime: SetupRuntime,
    #[arg(long, help = "Project directory (default: current dir)")]
    pub dir: Option<String>,
    #[arg(
        long,
        help = "Install globally in the selected runtime's configuration directory"
    )]
    pub global: bool,
    #[arg(long, help = "Remove hiboss hooks instead of adding")]
    pub remove: bool,
}

pub fn run_setup_hooks(args: &SetupHooksArgs) -> Result<(), Box<dyn Error>> {
    let (claude_dir, label) = super::setup_hook_files::destination(args)?;
    eprintln!("[hiboss]Target: {}", label);
    let settings_path = claude_dir.join(if args.runtime == SetupRuntime::Codex {
        "hooks.json"
    } else if args.global {
        "settings.json"
    } else {
        "settings.local.json"
    });
    let mut settings = super::setup_hook_files::read_settings(&settings_path)?;
    eprintln!("[hiboss]Loaded settings from {}", settings_path.display());
    let project_dir = if !args.global && !args.remove {
        Some(super::setup_hook_files::project_directory(args)?)
    } else {
        None
    };
    let project_dir_str = project_dir.as_ref().map(|dir| dir.to_string_lossy());
    let change = apply_hook_changes(
        &mut settings,
        args.remove,
        project_dir_str.as_deref(),
        args.runtime.profile(),
    )?;
    eprintln!("[hiboss]Computed hook updates");
    super::setup_hook_files::write_settings(&settings_path, &settings, change.changed)?;
    match change.action {
        HookAction::Added => println!("Added or refreshed hiboss lifecycle hooks"),
        HookAction::Removed => println!("Removed hiboss lifecycle hooks"),
        HookAction::None => println!("hiboss lifecycle hooks already configured"),
    }
    let instructions = if args.runtime == SetupRuntime::Codex {
        "AGENTS.md"
    } else {
        "CLAUDE.md"
    };
    if args.runtime == SetupRuntime::Codex && !args.remove {
        super::setup_agents::apply_profile_prompt_changes(&claude_dir.join(instructions), "codex")?;
    } else {
        apply_prompt_changes(&claude_dir.join(instructions), args.remove)?;
    }
    if args.runtime == SetupRuntime::Codex && !args.remove {
        println!("Review and trust the new HiBoss hooks in Codex /hooks before they can run.");
    }
    Ok(())
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
    runtime: &str,
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
        change.changed |= refresh_managed_hooks(event_value, project_dir, runtime)?;
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
        arr.push(new_hiboss_matcher(command_label, project_dir, runtime));
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
                let command = profile_hook_command(invocation, project_dir, runtime);
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

fn new_hiboss_matcher(command_label: &str, project_dir: Option<&str>, runtime: &str) -> Value {
    let command = profile_hook_command(command_label, project_dir, runtime);
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

fn profile_hook_command(command_label: &str, project_dir: Option<&str>, runtime: &str) -> String {
    let label = command_label
        .strip_prefix("--codex-input ")
        .unwrap_or(command_label);
    let command_label = if runtime == "codex" {
        format!("--codex-input {label}")
    } else {
        label.to_owned()
    };
    let command = if let Some(dir) = project_dir {
        format!(
            "HIBOSS_PROFILE={runtime} HIBOSS_PROJECT_DIR={} hiboss hook {}",
            shell_escape(dir),
            command_label
        )
    } else {
        format!("HIBOSS_PROFILE={runtime} hiboss hook {}", command_label)
    };
    command
}

fn shell_escape(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

#[cfg(test)]
#[path = "../tests/setup.rs"]
mod tests;
