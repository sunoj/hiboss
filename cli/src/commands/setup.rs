// Purpose: Manage Claude Code hook configuration for hiboss CLI.
// Exports: SetupArgs, SetupCommand, SetupHooksArgs, run.
// Dependencies: clap, serde_json, std::env, std::error, std::fs, std::path.

use clap::{Args, Subcommand};
use serde_json::{Map, Value};
use std::env;
use std::error::Error;
use std::fs;
use std::path::PathBuf;

const EVENT_COMMANDS: &[(&str, &str)] = &[
    ("SessionStart", "session-start"),
    ("PostToolUse", "post-tool-use"),
];

#[derive(Debug, Args)]
pub struct SetupArgs {
    #[command(subcommand)]
    pub command: SetupCommand,
}

#[derive(Debug, Subcommand)]
pub enum SetupCommand {
    #[command(about = "Configure Claude Code hooks for hiboss")]
    Hooks(SetupHooksArgs),
}

#[derive(Debug, Args)]
pub struct SetupHooksArgs {
    #[arg(long, help = "Project directory (default: current dir)")]
    pub dir: Option<String>,
    #[arg(long, help = "Install to global ~/.claude/settings.json")]
    pub global: bool,
    #[arg(long, help = "Remove hiboss hooks instead of adding")]
    pub remove: bool,
}

pub fn run(args: &SetupArgs) -> Result<(), Box<dyn Error>> {
    match &args.command {
        SetupCommand::Hooks(hooks_args) => run_setup_hooks(hooks_args),
    }
}

fn run_setup_hooks(args: &SetupHooksArgs) -> Result<(), Box<dyn Error>> {
    let (claude_dir, label) = if args.global {
        let home = env::var("HOME").map_err(|_| "HOME not set")?;
        (PathBuf::from(home).join(".claude"), "global ~/.claude".to_string())
    } else {
        let project_dir = if let Some(dir) = &args.dir {
            PathBuf::from(dir)
        } else {
            env::current_dir()?
        };
        (project_dir.join(".claude"), format!("{}", project_dir.display()))
    };
    eprintln!("[hiboss]Target: {}", label);

    let settings_path = claude_dir.join("settings.json");
    let mut settings = if settings_path.exists() {
        let contents = fs::read_to_string(&settings_path)?;
        let parsed = serde_json::from_str::<Value>(&contents)?;
        match parsed {
            Value::Object(_) => parsed,
            _ => return Err("settings.json must contain an object".into()),
        }
    } else {
        Value::Object(Map::new())
    };
    eprintln!("[hiboss]Loaded settings from {}", settings_path.display());

    let change = apply_hook_changes(&mut settings, args.remove)?;
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
        HookAction::Added => println!("Added hiboss hooks to .claude/settings.json"),
        HookAction::Removed => println!("Removed hiboss hooks from .claude/settings.json"),
        HookAction::None => println!("hiboss hooks already configured in .claude/settings.json"),
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

fn apply_hook_changes(settings: &mut Value, remove: bool) -> Result<HookChange, Box<dyn Error>> {
    let root = settings
        .as_object_mut()
        .ok_or("settings.json must contain an object")?;

    if remove {
        if let Some(hooks_value) = root.get_mut("hooks") {
            if !hooks_value.is_object() {
                return Err("hooks must be an object".into());
            }
            let mut change = HookChange::default();
            let mut drop_hooks = false;
            {
                let hooks_map = hooks_value.as_object_mut().unwrap();
                let mut to_remove = Vec::new();
                for (event, _) in EVENT_COMMANDS {
                    if let Some(event_value) = hooks_map.get_mut(*event) {
                        let arr = event_value
                            .as_array_mut()
                            .ok_or_else(|| format!("hooks.{} must be an array", event))?;
                        let original_len = arr.len();
                        arr.retain(|matcher| !matcher_contains_hiboss(matcher));
                        if arr.len() != original_len {
                            change.changed = true;
                            change.action = HookAction::Removed;
                        }
                        if arr.is_empty() {
                            to_remove.push(event.to_string());
                        }
                    }
                }
                for event in to_remove {
                    hooks_map.remove(&event);
                }
                if hooks_map.is_empty() {
                    drop_hooks = true;
                }
            }
            if drop_hooks {
                root.remove("hooks");
            }
            return Ok(change);
        }
        return Ok(HookChange::default());
    }

    let hooks_value = root.entry("hooks").or_insert_with(|| Value::Object(Map::new()));
    if !hooks_value.is_object() {
        return Err("hooks must be an object".into());
    }
    let mut change = HookChange::default();
    {
        let hooks_map = hooks_value.as_object_mut().unwrap();
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
            arr.push(new_hiboss_matcher(command_label));
            change.changed = true;
            change.action = HookAction::Added;
        }
    }
    Ok(change)
}

fn matcher_contains_hiboss(value: &Value) -> bool {
    value
        .get("hooks")
        .and_then(Value::as_array)
        .map(|hooks| {
            hooks.iter().any(|hook| {
                hook
                    .get("command")
                    .and_then(Value::as_str)
                    .map(|cmd| cmd.contains("hiboss hook"))
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false)
}

fn new_hiboss_matcher(command_label: &str) -> Value {
    let mut hook_obj = Map::new();
    hook_obj.insert("type".to_string(), Value::String("command".to_string()));
    hook_obj.insert(
        "command".to_string(),
        Value::String(format!("hiboss hook {}", command_label)),
    );
    let mut matcher_obj = Map::new();
    matcher_obj.insert("matcher".to_string(), Value::String(String::new()));
    matcher_obj.insert("hooks".to_string(), Value::Array(vec![Value::Object(hook_obj)]));
    Value::Object(matcher_obj)
}
