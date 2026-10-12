// Installs or removes lifecycle hooks across the selected runtime configuration paths.
// Exports run_setup_hooks; each destination reports a result independently.
// Dependencies: setup_hooks, setup_hook_files, claude_profiles, setup_agents.

use super::setup_hooks::{HookAction, SetupHooksArgs, SetupRuntime, apply_hook_changes};
use std::{
    error::Error,
    path::{Path, PathBuf},
};

pub fn run_setup_hooks(args: &SetupHooksArgs) -> Result<(), Box<dyn Error>> {
    let paths = destinations(args)?;
    let mut failed = false;
    for path in paths {
        match install(args, &path) {
            Ok(action) => {
                let result = match action {
                    HookAction::Added => "hooks installed / refreshed",
                    HookAction::Removed => "hooks removed",
                    HookAction::None if args.remove => "no hiboss hooks to remove",
                    HookAction::None => "hooks already installed",
                };
                println!("{}: {result}", path.display());
            }
            Err(error) => {
                eprintln!("{}: hook setup failed: {error}", path.display());
                failed = true;
            }
        }
    }
    if failed {
        return Err(
            "Some profiles could not be updated; repair the reported settings and retry".into(),
        );
    }
    if args.runtime == SetupRuntime::Codex && !args.remove {
        eprintln!("Review and trust the new HiBoss hooks in Codex /hooks before they can run.");
    }
    Ok(())
}

fn destinations(args: &SetupHooksArgs) -> Result<Vec<PathBuf>, Box<dyn Error>> {
    if let Some(path) = &args.config_dir {
        return Ok(vec![super::claude_profiles::absolute(path)?]);
    }
    if args.global && args.runtime == SetupRuntime::Claude {
        return super::claude_profiles::discover();
    }
    Ok(vec![super::setup_hook_files::destination(args)?.0])
}

fn install(args: &SetupHooksArgs, path: &Path) -> Result<HookAction, Box<dyn Error>> {
    let global = args.global || args.config_dir.is_some();
    let filename = match args.runtime {
        SetupRuntime::Codex => "hooks.json",
        SetupRuntime::Claude if global => "settings.json",
        SetupRuntime::Claude => "settings.local.json",
    };
    let settings_path = path.join(filename);
    let mut settings = super::setup_hook_files::read_settings(&settings_path)?;
    let project = if !global && !args.remove {
        Some(super::setup_hook_files::project_directory(args)?)
    } else {
        None
    };
    let project = project.as_ref().map(|path| path.to_string_lossy());
    let change = apply_hook_changes(
        &mut settings,
        args.remove,
        project.as_deref(),
        args.runtime.profile(),
    )?;
    super::setup_hook_files::write_settings(&settings_path, &settings, change.changed)?;
    let instructions = if args.runtime == SetupRuntime::Codex {
        "AGENTS.md"
    } else {
        "CLAUDE.md"
    };
    if args.runtime == SetupRuntime::Codex && !args.remove {
        super::setup_agents::apply_profile_prompt_changes(&path.join(instructions), "codex")?;
    } else {
        super::setup_agents::apply_prompt_changes(&path.join(instructions), args.remove)?;
    }
    Ok(change.action)
}
