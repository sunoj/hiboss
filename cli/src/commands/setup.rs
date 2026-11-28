// Dispatches local setup commands for hooks and agent guidance.
// Exports setup arguments and run; bare setup is handled by onboarding.

use crate::commands::setup_hooks;
use std::error::Error;

#[path = "setup_args.rs"]
mod arguments;
pub use arguments::{SetupArgs, SetupCommand};

pub fn run(args: &SetupArgs) -> Result<(), Box<dyn Error>> {
    match &args.command {
        Some(SetupCommand::Hooks(a)) => setup_hooks::run_setup_hooks(a),
        Some(SetupCommand::Agents(a)) => crate::commands::setup_agents::run(a),
        None => unreachable!("bare setup is handled by onboarding"),
    }
}
