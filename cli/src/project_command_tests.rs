// Purpose: Verify new project command grammar and hidden old command compatibility.
// Exports: CLI parser tests; depends on the binary's Clap command definitions.
use super::*;
use clap::CommandFactory;

#[test]
fn project_commands_parse() {
    for args in [
        vec!["hiboss", "project", "show"],
        vec!["hiboss", "project", "set", "--display-name", "Repo", "--bio", "Ships", "--avatar", "avatar.png"],
        vec!["hiboss", "project", "aliases", "add", "old-name", "--project", "repo"],
        vec!["hiboss", "project", "aliases", "remove", "old-name"],
    ] {
        assert!(matches!(Cli::try_parse_from(args).expect("valid project command").command, Commands::Project(_)));
    }
}

#[test]
fn old_team_commands_still_parse_but_are_hidden() {
    assert!(Cli::try_parse_from(["hiboss", "progress", "team", "register", "--display-name", "Repo"]).is_ok());
    assert!(Cli::try_parse_from(["hiboss", "progress", "team", "set-avatar", "avatar.png"]).is_ok());
    let mut command = Cli::command();
    let progress = command.find_subcommand_mut("progress").expect("progress command");
    assert!(!progress.render_help().to_string().contains("team"));
    let project = command.find_subcommand_mut("project").expect("project command");
    let help = project.render_help().to_string();
    assert!(help.contains("aliases"));
    assert!(help.contains("set"));
    assert!(!help.contains("register"));
}
