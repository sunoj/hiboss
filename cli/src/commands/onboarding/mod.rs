// Orchestrates grouped machine enrollment, approval persistence, and runtime guidance.
// Exports async run for bare `hiboss setup`; a pending request is resumed, never re-sent.
// Dependencies: typed enrollment API, config v2, existing Claude hooks and agent guidance.

pub(crate) mod api;
mod pending;
mod persistence;
mod poll;
mod resume;
pub(crate) mod selection;

use super::setup::SetupArgs;
use crate::config;
use std::{
    error::Error,
    io::{self, Write},
    path::PathBuf,
};

pub async fn run(args: &SetupArgs) -> Result<(), Box<dyn Error>> {
    if args.check {
        return check(&config::load_saved_config()?).await;
    }
    let _enrollment = config::ConfigLock::begin_enrollment(&config::config_path())?;
    if args.abandon {
        return resume::abandon();
    }
    let config = config::load_saved_config()?;
    if std::env::var_os("HIBOSS_KEY").is_some() || std::env::var_os("HIBOSS_SERVER").is_some() {
        return Err(
            "Setup saves device credentials; unset ephemeral HIBOSS_KEY and HIBOSS_SERVER first"
                .into(),
        );
    }
    let plan = match pending::load()? {
        Some(entry) => resume::resume(args, &config, entry).await?,
        None => match enroll(args, &config).await? {
            Some(plan) => plan,
            None => return Ok(()),
        },
    };
    println!("Approved. Saved credentials for every requested profile.");
    install_profiles(&plan)
}

/// Sends a new join request; None means there was nothing to enroll.
async fn enroll(
    args: &SetupArgs,
    config: &config::Config,
) -> Result<Option<selection::Plan>, Box<dyn Error>> {
    let plan = selection::build_plan(args, config)?;
    if plan.profiles.is_empty() {
        println!("No new profiles to enroll; use --profile <name> or install a supported runtime");
        return Ok(None);
    }
    confirm(&plan, args.yes)?;
    let joined = api::join(&api::http()?, &plan, args).await?;
    if joined.request_id.is_empty() || joined.poll_token.is_empty() {
        return Err("Invalid join receipt".into());
    }
    match joined.state.status.as_str() {
        "approved" => resume::settle(&plan, joined.state)?,
        "pending" => {
            show_code(joined.state.verification_code.as_deref())?;
            resume::record(&plan, &joined);
            resume::wait_and_save(&plan, &joined.poll_token, args.wait).await?;
        }
        "rejected" => return Err("The boss rejected this machine's join request".into()),
        _ => return Err("Invalid join status from HiBoss".into()),
    }
    Ok(Some(plan))
}

fn confirm(plan: &selection::Plan, yes: bool) -> Result<(), Box<dyn Error>> {
    println!("Request approval for {} on {}:", plan.label, plan.server);
    for entry in &plan.profiles {
        println!("  {}  {}", entry.profile, entry.name);
    }
    if yes {
        return Ok(());
    }
    eprint!("Continue? [y/N] ");
    io::stderr().flush()?;
    let mut answer = String::new();
    io::stdin().read_line(&mut answer)?;
    if !matches!(answer.trim().to_ascii_lowercase().as_str(), "y" | "yes") {
        return Err("Setup cancelled; no join request was sent".into());
    }
    Ok(())
}

fn show_code(code: Option<&str>) -> Result<(), Box<dyn Error>> {
    let code = code
        .filter(|code| code.len() == 6 && code.bytes().all(|byte| byte.is_ascii_digit()))
        .ok_or("Pending approval did not include a six-digit verification code")?;
    println!("\nVERIFICATION CODE: {code}\n");
    println!("Approve this code in HiBoss on iPhone/Mac or in Telegram. Waiting for the boss...");
    io::stdout().flush()?;
    Ok(())
}

fn install_profiles(plan: &selection::Plan) -> Result<(), Box<dyn Error>> {
    for entry in &plan.profiles {
        let result = match entry.profile.as_str() {
            "claude" => super::setup_hooks::run_setup_hooks(&super::setup_hooks::SetupHooksArgs {
                global: true,
                dir: None,
                remove: false,
            }),
            "codex" => guidance_path("CODEX_HOME", ".codex", "AGENTS.md", "codex"),
            "gemini" => guidance_path("", ".gemini", "GEMINI.md", "gemini"),
            _ => Ok(()),
        };
        result.map_err(|_| format!("Credentials saved, but {} integration failed; repair its settings and rerun hiboss setup hooks --global or setup agents", entry.profile))?;
    }
    Ok(())
}

fn guidance_path(
    variable: &str,
    directory: &str,
    file: &str,
    profile: &str,
) -> Result<(), Box<dyn Error>> {
    let base = std::env::var_os(variable)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| dirs::home_dir().map(|home| home.join(directory)))
        .ok_or("Cannot find runtime config directory")?;
    super::setup_agents::apply_profile_prompt_changes(&base.join(file), profile)
}

async fn check(config: &config::Config) -> Result<(), Box<dyn Error>> {
    if config.profiles.is_empty() {
        return Err("No profiles configured; run hiboss setup --server <url>".into());
    }
    let http = api::http()?;
    println!("{:<32} {:<6} DETAILS", "PROFILE", "RESULT");
    let mut failed = false;
    for (name, profile) in &config.profiles {
        let result = check_profile(&http, config, profile).await;
        match result {
            Ok(()) => println!("{name:<32} PASS   Identity verified"),
            Err(_) => {
                println!("{name:<32} FAIL   Identity check failed; verify server and enrollment");
                failed = true;
            }
        }
    }
    if failed {
        Err("One or more profile checks failed".into())
    } else {
        Ok(())
    }
}

async fn check_profile(
    http: &reqwest::Client,
    config: &config::Config,
    profile: &config::Profile,
) -> Result<(), Box<dyn Error>> {
    let server = selection::normalize_server(
        profile
            .server
            .as_deref()
            .or(config.server.as_deref())
            .ok_or("Server missing")?,
    )?;
    let key = profile
        .key
        .as_deref()
        .filter(|key| !key.is_empty())
        .ok_or("Key missing")?;
    let identity: serde_json::Value =
        api::response(http.get(format!("{server}/api/agents/me")).bearer_auth(key)).await?;
    let agent = identity.get("agent").unwrap_or(&identity);
    let id = agent
        .get("id")
        .and_then(serde_json::Value::as_str)
        .filter(|id| !id.is_empty())
        .ok_or("Identity missing")?;
    if profile
        .agent_id
        .as_deref()
        .is_some_and(|expected| expected != id)
    {
        return Err("Identity mismatch".into());
    }
    Ok(())
}
