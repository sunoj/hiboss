// Purpose: Claude Code hooks configuration for hiboss CLI.
// Exports: SetupHooksArgs, run_setup_hooks.
// Dependencies: clap, serde_json, std::env, std::fs, std::io, std::path.

use clap::Args;
use serde_json::{Map, Value};
use std::env;
use std::error::Error;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;

const EVENT_COMMANDS: &[(&str, &str)] = &[
    ("SessionStart", "session-start"),
    ("PostToolUse", "post-tool-use"),
    ("Stop", "stop"),
];

const PROMPT_BEGIN: &str = "<!-- hiboss:begin -->";
const PROMPT_END: &str = "<!-- hiboss:end -->";

const GLOBAL_PROMPT: &str = r#"<!-- hiboss:begin -->
## hiboss — Boss Communication

Use `hiboss` to communicate with your boss: `send "msg"`, `ask "question"`, `inbox`, `reply <id> "msg"`.
When task is complete, NEVER just stop. Run `hiboss ask --option "A" --option "B" --option "C" "summary + options"` (background), wait for reply.
Use only repeatable singular `--option` / `--action`; never use removed `--options` / `--actions` or comma-join choices.
<!-- hiboss:end -->"#;

#[derive(Debug, Args)]
pub struct SetupHooksArgs {
    #[arg(long, help = "Project directory (default: current dir)")]
    pub dir: Option<String>,
    #[arg(long, help = "Install to global ~/.claude/settings")]
    pub global: bool,
    #[arg(long, help = "Remove hiboss hooks instead of adding")]
    pub remove: bool,
}

pub fn run_setup_hooks(args: &SetupHooksArgs) -> Result<(), Box<dyn Error>> {
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

    // Project-local hooks use settings.local.json (gitignored, contains machine-specific paths)
    let settings_file = if args.global { "settings.json" } else { "settings.local.json" };
    let settings_path = claude_dir.join(settings_file);
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

    // For project-local setup, bake project dir into hook commands via env var
    let project_dir_str = if !args.global && !args.remove {
        let dir = if let Some(dir) = &args.dir {
            PathBuf::from(dir)
        } else {
            env::current_dir()?
        };
        Some(dir.to_string_lossy().to_string())
    } else {
        None
    };
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
        HookAction::Added => println!("Added hiboss hooks to .claude/settings"),
        HookAction::Removed => println!("Removed hiboss hooks from .claude/settings"),
        HookAction::None => println!("hiboss hooks already configured in .claude/settings"),
    }

    let claude_md_path = claude_dir.join("CLAUDE.md");
    apply_prompt_changes(&claude_md_path, args.remove)?;
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HookAction { Added, Removed, None }

#[derive(Debug)]
struct HookChange { changed: bool, action: HookAction }

impl Default for HookChange {
    fn default() -> Self { Self { changed: false, action: HookAction::None } }
}

fn apply_hook_changes(settings: &mut Value, remove: bool, project_dir: Option<&str>) -> Result<HookChange, Box<dyn Error>> {
    let root = settings.as_object_mut().ok_or("settings.json must contain an object")?;

    if remove {
        if let Some(hooks_value) = root.get_mut("hooks") {
            if !hooks_value.is_object() { return Err("hooks must be an object".into()); }
            let mut change = HookChange::default();
            let mut drop_hooks = false;
            {
                let hooks_map = hooks_value.as_object_mut().unwrap();
                let mut to_remove = Vec::new();
                for (event, _) in EVENT_COMMANDS {
                    if let Some(event_value) = hooks_map.get_mut(*event) {
                        let arr = event_value.as_array_mut()
                            .ok_or_else(|| format!("hooks.{} must be an array", event))?;
                        let original_len = arr.len();
                        arr.retain(|matcher| !matcher_contains_hiboss(matcher));
                        if arr.len() != original_len {
                            change.changed = true;
                            change.action = HookAction::Removed;
                        }
                        if arr.is_empty() { to_remove.push(event.to_string()); }
                    }
                }
                for event in to_remove { hooks_map.remove(&event); }
                if hooks_map.is_empty() { drop_hooks = true; }
            }
            if drop_hooks { root.remove("hooks"); }
            return Ok(change);
        }
        return Ok(HookChange::default());
    }

    let hooks_value = root.entry("hooks").or_insert_with(|| Value::Object(Map::new()));
    if !hooks_value.is_object() { return Err("hooks must be an object".into()); }
    let mut change = HookChange::default();
    {
        let hooks_map = hooks_value.as_object_mut().unwrap();
        for (event, command_label) in EVENT_COMMANDS {
            let entry = hooks_map.entry(event.to_string()).or_insert_with(|| Value::Array(vec![]));
            let arr = entry.as_array_mut()
                .ok_or_else(|| format!("hooks.{} must be an array", event))?;
            if arr.iter().any(matcher_contains_hiboss) { continue; }
            arr.push(new_hiboss_matcher(command_label, project_dir));
            change.changed = true;
            change.action = HookAction::Added;
        }
    }
    Ok(change)
}

fn apply_prompt_changes(path: &PathBuf, remove: bool) -> Result<(), Box<dyn Error>> {
    let existing = if path.exists() { fs::read_to_string(path)? } else { String::new() };
    let has_prompt = existing.contains(PROMPT_BEGIN);

    if remove {
        if !has_prompt { return Ok(()); }
        let mut result = String::new();
        let mut skipping = false;
        for line in existing.lines() {
            if line.contains(PROMPT_BEGIN) { skipping = true; continue; }
            if line.contains(PROMPT_END) { skipping = false; continue; }
            if !skipping { result.push_str(line); result.push('\n'); }
        }
        let trimmed = result.trim_end().to_string();
        let content = if trimmed.is_empty() { String::new() } else { format!("{}\n", trimmed) };
        fs::write(path, content)?;
        println!("Removed hiboss prompt from {}", path.display());
        return Ok(());
    }

    if has_prompt { return Ok(()); }

    eprintln!("\nThe following will be appended to {}:\n", path.display());
    eprintln!("{}\n", GLOBAL_PROMPT);
    eprint!("Add hiboss prompt to CLAUDE.md? [y/N] ");
    io::stderr().flush()?;
    let mut answer = String::new();
    io::stdin().read_line(&mut answer)?;
    if !answer.trim().eq_ignore_ascii_case("y") {
        eprintln!("Skipped CLAUDE.md prompt injection.");
        return Ok(());
    }

    let mut content = existing;
    if !content.is_empty() && !content.ends_with('\n') { content.push('\n'); }
    if !content.is_empty() { content.push('\n'); }
    content.push_str(GLOBAL_PROMPT);
    content.push('\n');
    if let Some(parent) = path.parent() { fs::create_dir_all(parent)?; }
    fs::write(path, content)?;
    println!("Added hiboss prompt to {}", path.display());
    Ok(())
}

fn matcher_contains_hiboss(value: &Value) -> bool {
    value.get("hooks").and_then(Value::as_array).map(|hooks| {
        hooks.iter().any(|hook| {
            hook.get("command").and_then(Value::as_str)
                .map(|cmd| cmd.contains("hiboss hook"))
                .unwrap_or(false)
        })
    }).unwrap_or(false)
}

fn new_hiboss_matcher(command_label: &str, project_dir: Option<&str>) -> Value {
    let command = if let Some(dir) = project_dir {
        format!("HIBOSS_PROJECT_DIR={} hiboss hook {}", shell_escape(dir), command_label)
    } else {
        format!("hiboss hook {}", command_label)
    };
    let mut hook_obj = Map::new();
    hook_obj.insert("type".to_string(), Value::String("command".to_string()));
    hook_obj.insert("command".to_string(), Value::String(command));
    let mut matcher_obj = Map::new();
    matcher_obj.insert("matcher".to_string(), Value::String(String::new()));
    matcher_obj.insert("hooks".to_string(), Value::Array(vec![Value::Object(hook_obj)]));
    Value::Object(matcher_obj)
}

fn shell_escape(s: &str) -> String {
    if s.contains(|c: char| c.is_whitespace() || c == '\'' || c == '"' || c == '$' || c == '\\') {
        format!("'{}'", s.replace('\'', "'\\''"))
    } else {
        s.to_string()
    }
}
