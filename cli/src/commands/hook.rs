// Purpose: Provide the Claude Code hook orchestration for hiboss CLI events.
// Exports: HookArgs, HookEvent, run().
// Dependencies: clap, std::fs, std::process, std::time.

use clap::{Args, Subcommand};
use std::error::Error;
use std::fs;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const TTL_FILE: &str = "/tmp/hiboss-urgent-check";
const TTL_SECONDS: u64 = 300;

#[derive(Debug, Args)]
pub struct HookArgs {
    #[command(subcommand)]
    pub event: HookEvent,
}

#[derive(Debug, Subcommand)]
pub enum HookEvent {
    #[command(about = "Check unread messages at session start")]
    SessionStart,
    #[command(about = "Check urgent messages (TTL-cached, 5 min)")]
    PostToolUse,
    #[command(about = "Remind about unread messages before stopping")]
    Stop,
}

pub async fn run(args: &HookArgs) -> Result<(), Box<dyn Error>> {
    let _ = match &args.event {
        HookEvent::SessionStart => run_session_start(),
        HookEvent::PostToolUse => run_post_tool_use(),
        HookEvent::Stop => run_stop(),
    };
    Ok(())
}

fn run_session_start() -> Result<(), Box<dyn Error>> {
    let count = get_inbox_count();
    if count > 0 {
        println!("You have {} unread boss messages:", count);
        if let Ok(out) = Command::new("hiboss").args(["inbox", "--ack"]).output() {
            print!("{}", String::from_utf8_lossy(&out.stdout));
        }
        println!("Handle these messages before starting other work. Use 'hiboss reply <id> \"response\"' to reply.");
    }
    Ok(())
}

fn run_post_tool_use() -> Result<(), Box<dyn Error>> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    if let Ok(content) = fs::read_to_string(TTL_FILE) {
        if let Ok(last_check) = content.trim().parse::<u64>() {
            if now.saturating_sub(last_check) < TTL_SECONDS {
                return Ok(());
            }
        }
    }

    let _ = fs::write(TTL_FILE, now.to_string());
    let count = get_priority_inbox_count("critical,high");
    if count > 0 {
        println!("URGENT: You have {} unread critical/high priority boss messages. Run: hiboss inbox --priority critical,high", count);
    }
    Ok(())
}

fn run_stop() -> Result<(), Box<dyn Error>> {
    let count = get_inbox_count();
    if count > 0 {
        println!("You have {} unread boss messages. Run 'hiboss inbox' and handle them before finishing.", count);
    } else {
        println!("[hiboss] No unread boss messages.");
    }
    Ok(())
}

fn get_inbox_count() -> u32 {
    let output = Command::new("hiboss").args(["inbox", "--count"]).output().ok();
    output
        .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse().ok())
        .unwrap_or(0)
}

fn get_priority_inbox_count(priority: &str) -> u32 {
    let output = Command::new("hiboss")
        .args(["inbox", "--priority", priority, "--count"])
        .output()
        .ok();
    output
        .and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse().ok())
        .unwrap_or(0)
}
