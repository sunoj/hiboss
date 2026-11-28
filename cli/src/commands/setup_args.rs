// Defines machine onboarding arguments and local setup subcommands.
// Exports setup argument structs and the subcommand enum.
// Dependencies: clap and SetupHooksArgs.
use crate::commands::setup_hooks::SetupHooksArgs;
use clap::{Args, Subcommand};

#[derive(Debug, Args)]
pub struct SetupArgs {
    #[command(subcommand)]
    pub command: Option<SetupCommand>,
    #[arg(long, help = "HiBoss server URL (otherwise existing config)")]
    pub server: Option<String>,
    #[arg(long, help = "Single-use Add a machine invite")]
    pub invite: Option<String>,
    #[arg(long, help = "Runtime profile to set up; repeat for each profile")]
    pub profile: Vec<String>,
    #[arg(long, help = "Machine label used to distinguish agent names")]
    pub label: Option<String>,
    #[arg(long, help = "First-device bootstrap secret")]
    pub bootstrap_secret: Option<String>,
    #[arg(long, help = "Name of the first boss")]
    pub boss_name: Option<String>,
    #[arg(long, help = "Accept the proposed runtime profiles")]
    pub yes: bool,
    #[arg(long, help = "Verify each configured profile against the server")]
    pub check: bool,
    #[arg(long, help = "Discard a pending join request without polling")]
    pub abandon: bool,
    #[arg(
        long,
        value_name = "SECONDS",
        default_value_t = 1800,
        value_parser = clap::value_parser!(u64).range(1..=86_400),
        help = "How long to wait for approval; rerun setup to keep waiting"
    )]
    pub wait: u64,
}

#[derive(Debug, Subcommand)]
pub enum SetupCommand {
    #[command(
        about = "Install or refresh global Codex and Claude HiBoss delivery and questionnaire guidance"
    )]
    Agents(crate::commands::setup_agents::SetupAgentsArgs),
    #[command(about = "Configure Claude Code hooks for hiboss")]
    Hooks(SetupHooksArgs),
}
