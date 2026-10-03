// Purpose: Display the locally resolved agent credential without a network request.
// Exports: WhoamiArgs and run.
// Dependencies: clap, serde_json, crate::config.

use crate::config::{self, Config};
use clap::Args;
use std::error::Error;

#[derive(Debug, Args)]
pub struct WhoamiArgs {
    #[arg(long)]
    pub json: bool,
}

pub fn run(args: &WhoamiArgs, config: &Config) -> Result<(), Box<dyn Error>> {
    let credential = config::resolve_credentials(config)?;
    let key = mask_key(&credential.key);
    let path = config::config_path().display().to_string();
    if args.json {
        println!(
            "{}",
            serde_json::json!({
                "profile": credential.profile, "source_rule": credential.source_rule,
                "agent_name": credential.name, "server": credential.server,
                "config_path": path, "runtime": credential.runtime.runtime, "key": key
            })
        );
    } else {
        println!(
            "Profile: {}\nSource rule: {}\nAgent: {}\nServer: {}\nConfig: {}\nRuntime: {}\nKey: {}",
            credential.profile,
            credential.source_rule,
            credential.name.as_deref().unwrap_or("unknown"),
            credential.server,
            path,
            credential.runtime.runtime,
            key
        );
    }
    Ok(())
}

pub(crate) fn mask_key(value: &str) -> String {
    if value.chars().count() <= 4 {
        return "...".into();
    }
    let tail: String = value
        .chars()
        .rev()
        .take(4)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    format!("...{tail}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn masks_all_but_four_trailing_characters() {
        assert_eq!(mask_key("hb_123456"), "...3456");
        assert_eq!(mask_key("abc"), "...");
    }
}
