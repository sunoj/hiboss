// Purpose: Aggregate hiboss CLI command modules for easier imports.
// Exports: command modules and the required SubcommandArgs envelope.
// Dependencies: none beyond the command modules themselves.

// A required nested command with its original typed leaf options.
#[derive(Debug, clap::Args)]
pub struct SubcommandArgs<C: clap::Subcommand> {
    #[command(subcommand)]
    pub command: C,
}

pub mod agent;
pub mod ask;
pub(crate) mod ask_media;
pub(crate) mod ask_descriptions;
mod ask_support;
mod ask_result;
mod ask_wait;
pub mod boss;
#[path = "box/mod.rs"]
pub mod box_cmd;
pub mod bot;
pub mod channel;
pub mod config;
pub mod daemon;
pub mod device;
pub mod doctor;
pub mod edit;
pub mod forward;
pub mod group;
pub mod hook;
mod codex_hook;
mod setup_hook_files;
mod setup_hook_commands;
mod setup_hook_install;
mod setup_json_edit;
mod setup_json_spans;
mod claude_profiles;
mod hook_start;
pub(crate) mod hook_helpers;
pub(crate) mod hook_unacked;
pub mod inbox;
pub mod key;
pub mod onboarding;
pub mod react;
pub mod read;
pub mod reply;
pub mod route;
pub mod progress;
pub mod panel;
pub mod request;
pub mod send;
mod message_text;
pub(crate) mod send_metadata;
pub(crate) mod session_register;
pub mod setup;
pub mod setup_agents;
pub mod setup_hooks;
pub mod ss;
pub mod status;
mod status_result;
pub mod watch;
pub mod whoami;
