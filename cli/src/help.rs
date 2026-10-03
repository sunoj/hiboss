// Purpose: Render the root `hiboss --help` as commands grouped by intent plus examples.
// Exports: COMMAND_GROUPS, grouped_root_command.
// Dependencies: clap::Command (descriptions come from each subcommand's own `about`).

use clap::Command;

/// Root subcommands grouped by what the user is trying to do. Every visible
/// subcommand appears in exactly one group; a unit test enforces that.
pub const COMMAND_GROUPS: &[(&str, &[&str])] = &[
    (
        "Get started",
        &["setup", "device", "doctor", "whoami", "config"],
    ),
    (
        "Talk to your boss",
        &[
            "send", "ask", "reply", "inbox", "read", "react", "edit", "forward", "status",
        ],
    ),
    ("Show work", &["panel", "request", "progress", "project"]),
    ("Coordinate sessions", &["ss", "agent", "group"]),
    ("Run in the background", &["watch", "bot", "daemon", "hook"]),
    (
        "Administer the server",
        &["key", "boss", "channel", "route"],
    ),
];

const EXAMPLES: &str = "\
Examples:
  hiboss setup --server https://hiboss.example.com --invite <invite>  Join a machine for approval
  hiboss device invite                           Create an Add a machine invite
  hiboss doctor                                  Check configuration and connectivity
  hiboss send \"Build finished: 42 tests passed\"  Notify the boss without waiting
  hiboss ask \"Deploy to staging?\" --option Yes --option No
  hiboss inbox                                   List messages from the boss
  hiboss panel guide                             Read the live-panel guide (works offline)
  hiboss request list <panel-id>                 Read a panel's questionnaires as JSON

Run `hiboss <command> --help` for the flags of one command.";

/// Return `root` with grouped command help, examples, and help on a bare `hiboss`.
pub fn grouped_root_command(root: Command) -> Command {
    let template = format!(
        "{{about-with-newline}}\n{{usage-heading}} {{usage}}\n\n{}Options:\n{{options}}\n\n{EXAMPLES}",
        render_groups(&root)
    );
    root.help_template(template).arg_required_else_help(true)
}

fn render_groups(root: &Command) -> String {
    let width = COMMAND_GROUPS
        .iter()
        .flat_map(|(_, names)| names.iter())
        .map(|name| name.len())
        .max()
        .unwrap_or(0);
    let mut out = String::new();
    for (title, names) in COMMAND_GROUPS {
        out.push_str(&format!("{title}:\n"));
        for name in names.iter() {
            let about = root
                .find_subcommand(name)
                .and_then(|sub| sub.get_about())
                .map(|about| about.to_string())
                .unwrap_or_default();
            out.push_str(&format!("  {name:<width$}  {about}\n"));
        }
        out.push('\n');
    }
    out
}
