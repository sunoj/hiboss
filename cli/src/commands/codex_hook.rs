// Adapts Codex hook JSON to the existing HiBoss lifecycle command.
// Exports run; session and project context are scoped to a child process.
// Dependencies: serde_json, stdin, and the current executable; no shell evaluation.

use super::hook::HookEvent;
use serde::Deserialize;
use std::{error::Error, io::Read, process::Command};

#[derive(Deserialize)]
struct Input {
    session_id: String,
    cwd: String,
}

pub(super) fn run(event: &HookEvent) -> Result<(), Box<dyn Error>> {
    let mut text = String::new();
    std::io::stdin().take(65_537).read_to_string(&mut text)?;
    if text.len() > 65_536 {
        return Err("Codex hook input exceeds 64 KiB".into());
    }
    let input: Input = serde_json::from_str(&text)?;
    if input.session_id.trim().is_empty() || input.cwd.trim().is_empty() {
        return Err("Codex hook needs session_id and cwd".into());
    }
    let (event, name) = match event {
        HookEvent::SessionStart => ("session-start", "SessionStart"),
        HookEvent::PostToolUse => ("post-tool-use", "PostToolUse"),
        HookEvent::Stop => ("stop", "Stop"),
        HookEvent::BgCheck => ("bg-check", "PostToolUse"),
    };
    let output = Command::new(std::env::current_exe()?)
        .args(["hook", event])
        .env("HIBOSS_PROFILE", "codex")
        .env("CODEX_THREAD_ID", input.session_id)
        .env("HIBOSS_PROJECT_DIR", &input.cwd)
        .current_dir(input.cwd)
        .stdin(std::process::Stdio::null())
        .output()?;
    eprint!("{}", String::from_utf8_lossy(&output.stderr));
    if !output.status.success() {
        return Err("Codex lifecycle command failed".into());
    }
    let text = String::from_utf8_lossy(&output.stdout);
    if name == "Stop" {
        println!("{}", serde_json::json!({"systemMessage": text.trim()}));
    } else {
        println!(
            "{}",
            serde_json::json!({"hookSpecificOutput": {
                "hookEventName": name, "additionalContext": text
            }})
        );
    }
    Ok(())
}
