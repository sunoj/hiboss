// Mints a single-use device invite and renders a self-contained onboarding prompt.
// Exports DeviceArgs and run; only the invite is printed or copied, never agent keys.
// Dependencies: resolved config, bounded HTTP transport, and platform clipboard commands.

use super::onboarding::{api, selection::normalize_server};
use crate::config::{self, Config};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use std::{
    error::Error,
    io::Write,
    process::{Command, Stdio},
};

#[derive(Debug, Args)]
pub struct DeviceArgs {
    #[command(subcommand)]
    pub command: DeviceCommand,
}

#[derive(Debug, Subcommand)]
pub enum DeviceCommand {
    #[command(about = "Print a single-use prompt to enroll a new machine")]
    Invite(InviteArgs),
}

#[derive(Debug, Args)]
pub struct InviteArgs {
    #[arg(long, help = "Also copy the onboarding prompt to the clipboard")]
    pub copy: bool,
    #[arg(long, help = "Print invite metadata and the prompt as JSON")]
    pub json: bool,
}

#[derive(Deserialize, Serialize)]
struct Invite {
    invite: String,
    expires_at: String,
    inviter_label: String,
}

pub async fn run(args: &DeviceArgs, config: &Config) -> Result<(), Box<dyn Error>> {
    let DeviceCommand::Invite(args) = &args.command;
    let credential = config::resolve_credentials(config)?;
    let server = normalize_server(&credential.server)?;
    let invite: Invite = api::response(
        api::http()?
            .post(format!("{server}/api/devices/invites"))
            .bearer_auth(&credential.key),
    )
    .await?;
    validate_invite(&invite)?;
    let prompt = invite_prompt(&server, &invite.invite, &invite.expires_at);
    if prompt.contains(&credential.key) || invite.inviter_label.contains(&credential.key) {
        return Err("Invalid device invite response".into());
    }
    if args.copy {
        match copy_prompt(&prompt) {
            Ok(true) => eprintln!("Onboarding prompt copied to the clipboard."),
            Ok(false) => eprintln!(
                "Clipboard unavailable: install pbcopy, wl-copy or xclip; copy the printed prompt."
            ),
            Err(_) => eprintln!("Clipboard copy failed; copy the printed prompt."),
        }
    }
    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({
                "invite": invite.invite, "expires_at": invite.expires_at,
                "inviter_label": invite.inviter_label, "prompt": prompt
            }))?
        );
    } else {
        println!("{prompt}");
    }
    Ok(())
}

fn validate_invite(invite: &Invite) -> Result<(), Box<dyn Error>> {
    let suffix = invite
        .invite
        .strip_prefix("hb_inv_")
        .ok_or("Invalid device invite response")?;
    if suffix.len() != 64
        || !suffix.bytes().all(|byte| byte.is_ascii_hexdigit())
        || invite.expires_at.is_empty()
        || invite.expires_at.chars().any(char::is_control)
    {
        return Err("Invalid device invite response".into());
    }
    Ok(())
}

fn invite_prompt(server: &str, invite: &str, expires_at: &str) -> String {
    format!(
        "Set up HiBoss on this machine and request approval from the boss.\n\
1. If `hiboss --version` fails, install it: cargo install --git https://github.com/sunoj/hiboss hiboss\n\
2. Run: hiboss setup --server {} --invite {}\n\
3. Tell the user the 6-digit verification code it prints, then wait until it reports approval.\n\
This invite expires at {expires_at} and works once.",
        shell_quote(server),
        shell_quote(invite)
    )
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn copy_prompt(prompt: &str) -> Result<bool, Box<dyn Error>> {
    for (program, args) in [
        ("pbcopy", &[][..]),
        ("wl-copy", &[][..]),
        ("xclip", &["-selection", "clipboard"][..]),
    ] {
        let mut child = match Command::new(program)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(child) => child,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error.into()),
        };
        let written = child
            .stdin
            .take()
            .ok_or("Clipboard stdin unavailable")?
            .write_all(prompt.as_bytes());
        let status = child.wait()?;
        if written.is_ok() && status.success() {
            return Ok(true);
        }
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn prompt_contains_only_invite_server_and_instructions() {
        let invite = format!("hb_inv_{}", "a".repeat(64));
        let key = "hb_secret_synthetic_agent_key";
        let prompt = invite_prompt("https://hiboss.example", &invite, "2026-10-03T12:00:00Z");
        assert!(prompt.contains(&invite));
        assert!(prompt.contains("https://hiboss.example"));
        assert!(prompt.contains("cargo install --git https://github.com/sunoj/hiboss hiboss"));
        assert!(prompt.contains("6-digit verification code"));
        assert!(prompt.contains("works once"));
        assert!(!prompt.contains(key));
        assert!(!prompt.contains("--key"));
    }
}
