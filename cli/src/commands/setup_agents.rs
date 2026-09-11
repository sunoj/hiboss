// Installs discoverable, refreshable HiBoss guidance for Codex and Claude agents.
// Exports SetupAgentsArgs, run, and embedded panel guide text.
// Dependencies: clap, dirs, and filesystem operations; no credentials or network.

use clap::Args;
use std::{error::Error, fs, path::{Path, PathBuf}};

pub const PANEL_GUIDE: &str = include_str!("../../resources/panel-agent-guide.md");
const BEGIN: &str = "<!-- hiboss:panels:begin -->";
const END: &str = "<!-- hiboss:panels:end -->";
pub(crate) const PROMPT: &str = include_str!("../../resources/agent-instructions.md");
const COMMUNICATION_BEGIN: &str = "<!-- hiboss:begin -->";
const COMMUNICATION_END: &str = "<!-- hiboss:end -->";

#[derive(Debug, Args)]
pub struct SetupAgentsArgs {
    #[arg(long, help = "Preview destinations and the managed global instruction block")]
    pub dry_run: bool,
    #[arg(long, help = "Agent home directory (default: current user's home)")]
    pub home_dir: Option<PathBuf>,
}

pub fn run(args: &SetupAgentsArgs) -> Result<(), Box<dyn Error>> {
    let home = args.home_dir.clone().or_else(dirs::home_dir).ok_or("Cannot find agent home directory")?;
    let guide = home.join(".config/hiboss/panel-agent-guide.md");
    let paths = [home.join(".codex/AGENTS.md"), home.join(".claude/CLAUDE.md")];
    let mut updates = Vec::new();
    for path in paths {
        let existing = if path.exists() { fs::read_to_string(&path)? } else { String::new() };
        updates.push((path, managed_content(&existing, false)?));
    }
    updates.push((guide, PANEL_GUIDE.to_owned()));
    if args.dry_run { println!("{PROMPT}\n"); }
    for (path, content) in updates {
        if args.dry_run { println!("Would update {}", path.display()); }
        else { write_atomic(&path, &content)?; println!("Updated {}", path.display()); }
    }
    Ok(())
}

fn replace_block(existing: &str, begin: &str, end: &str, replacement: &str) -> Result<String, Box<dyn Error>> {
    let starts: Vec<_> = existing.match_indices(begin).collect();
    let ends: Vec<_> = existing.match_indices(end).collect();
    if starts.is_empty() && ends.is_empty() { return Ok(existing.to_owned()); }
    if starts.len() != 1 || ends.len() != 1 || starts[0].0 >= ends[0].0 {
        return Err("Invalid HiBoss instruction block; repair its markers first".into());
    }
    let mut content = existing.to_owned();
    content.replace_range(starts[0].0..ends[0].0 + end.len(), replacement);
    Ok(content)
}

fn managed_content(existing: &str, remove: bool) -> Result<String, Box<dyn Error>> {
    let content = replace_block(existing, COMMUNICATION_BEGIN, COMMUNICATION_END, "")?;
    let replacement = if remove { "" } else { PROMPT.trim_end() };
    let updated = replace_block(&content, BEGIN, END, replacement)?;
    if remove || content.contains(BEGIN) { return Ok(updated); }
    Ok(format!("{}\n\n{}\n", updated.trim_end(), PROMPT.trim_end()))
}

pub(crate) fn apply_prompt_changes(path: &Path, remove: bool) -> Result<(), Box<dyn Error>> {
    if remove && !path.exists() { return Ok(()); }
    let existing = if path.exists() { fs::read_to_string(path)? } else { String::new() };
    let content = managed_content(&existing, remove)?;
    write_atomic(path, &content)?;
    println!("Updated HiBoss instructions in {}", path.display());
    Ok(())
}

fn write_atomic(path: &Path, content: &str) -> Result<(), Box<dyn Error>> {
    let parent = path.parent().ok_or("Invalid instruction destination")?;
    fs::create_dir_all(parent)?;
    let temporary = path.with_extension(format!("hiboss-{}.tmp", std::process::id()));
    fs::write(&temporary, content)?;
    if path.exists() { fs::set_permissions(&temporary, fs::metadata(path)?.permissions())?; }
    fs::rename(temporary, path)?;
    Ok(())
}
