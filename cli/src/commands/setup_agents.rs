// Installs discoverable, refreshable HiBoss guidance for Codex and Claude agents.
// Exports SetupAgentsArgs, run, and embedded panel guide text.
// Dependencies: clap, dirs, and filesystem operations; no credentials or network.

use clap::Args;
use std::{error::Error, fs, path::{Path, PathBuf}};

pub const PANEL_GUIDE: &str = include_str!("../../resources/panel-agent-guide.md");
const BEGIN: &str = "<!-- hiboss:panels:begin -->";
const END: &str = "<!-- hiboss:panels:end -->";
const PROMPT: &str = r#"<!-- hiboss:panels:begin -->
## HiBoss dynamic notifications and report delivery

- Dynamic notifications / live cards / Panels use `hiboss panel`.
- When asked to deliver task progress or a test report via HiBoss, read
  `~/.config/hiboss/panel-agent-guide.md`, then inspect `hiboss panel --help`.
- The guide contains the publication schema, recipient/session discovery,
  one-shot updates, streaming, lease recovery, lifecycle shortcuts, doctor,
  idempotency, and delivery verification.
- Use actual test counts, fixes, artifact location, and untested scope. Publishing
  a card does not upload a report file. Never invent accessible artifact URLs.
- `hiboss send` is a one-shot message; `hiboss ask` is for a required human decision.
  Report delivery itself does not require a blocking question.
- Check the installed interface and server protocol before using lifecycle
  commands. Report a version mismatch; never claim an unconfirmed delivery.
- Keep one panel per execution and update it. Retry the same command/key after an
  uncertain response; start a new run for a new execution. Never expose API keys.
<!-- hiboss:panels:end -->"#;

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
        updates.push((path, managed_content(&existing)?));
    }
    updates.push((guide, PANEL_GUIDE.to_owned()));
    if args.dry_run { println!("{PROMPT}\n"); }
    for (path, content) in updates {
        if args.dry_run { println!("Would update {}", path.display()); }
        else { write_atomic(&path, &content)?; println!("Updated {}", path.display()); }
    }
    Ok(())
}

fn managed_content(existing: &str) -> Result<String, Box<dyn Error>> {
    let mut content = existing.to_owned();
    if let Some(start) = content.find(BEGIN) {
        let end = content[start..].find(END).ok_or("Incomplete HiBoss instruction block; repair its markers first")? + start + END.len();
        content.replace_range(start..end, PROMPT);
        return Ok(content);
    }
    if content.contains(END) { return Err("Orphaned HiBoss instruction end marker".into()); }
    Ok(format!("{}\n\n{PROMPT}\n", existing.trim_end()))
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
