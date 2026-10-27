// Purpose: Keep the grouped root help in sync with the real subcommand list.
// Exports: unit tests; depends on the binary's Clap definitions and hiboss::help.
use super::*;
use clap::error::ErrorKind;
use help::{COMMAND_GROUPS, grouped_root_command};

#[test]
fn every_visible_command_is_in_exactly_one_group() {
    let root = Cli::command();
    let grouped: Vec<&str> = COMMAND_GROUPS
        .iter()
        .flat_map(|(_, names)| names.iter().copied())
        .collect();
    for sub in root.get_subcommands().filter(|sub| !sub.is_hide_set()) {
        let count = grouped
            .iter()
            .filter(|name| **name == sub.get_name())
            .count();
        assert_eq!(
            count,
            1,
            "{} must appear in exactly one group",
            sub.get_name()
        );
    }
    for name in grouped {
        assert!(
            root.find_subcommand(name).is_some(),
            "group names unknown command {name}"
        );
    }
}

#[test]
fn grouped_help_shows_descriptions_and_examples() {
    let help = grouped_root_command(Cli::command())
        .render_help()
        .to_string();
    assert!(help.contains("Get started:\n  setup "), "{help}");
    assert!(
        help.contains("Send a message, progress note, result or report to your boss"),
        "{help}"
    );
    assert!(help.contains("Examples:\n  hiboss setup --server https://"), "{help}");
    assert!(help.contains("Options:\n"), "{help}");
}

#[test]
fn bare_invocation_requests_help() {
    let err = grouped_root_command(Cli::command())
        .try_get_matches_from(["hiboss"])
        .expect_err("bare invocation shows help");
    assert_eq!(
        err.kind(),
        ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand
    );
    assert_eq!(err.exit_code(), 2);
    for path in [
        "agent", "device", "config", "channel", "route", "group", "boss", "daemon",
        "progress", "box", "project", "panel", "request", "progress team",
        "project aliases", "progress team aliases",
    ] {
        let args = std::iter::once("hiboss").chain(path.split_whitespace());
        let err = grouped_root_command(Cli::command()).try_get_matches_from(args)
            .expect_err("nested command is required");
        assert_eq!(err.exit_code(), 2, "{path}");
    }
}

#[test]
fn grouped_command_still_parses_subcommands() {
    let matches = grouped_root_command(Cli::command())
        .try_get_matches_from(["hiboss", "panel", "guide"])
        .expect("panel guide parses");
    let cli = Cli::from_arg_matches(&matches).expect("matches convert");
    assert!(matches!(cli.command,
        Commands::Panel(args) if matches!(&args.command, panel::PanelCommand::Guide)
    ));
    let matches = grouped_root_command(Cli::command())
        .try_get_matches_from(["hiboss", "request", "list", "panel-id"])
        .expect("questionnaire example parses");
    let cli = Cli::from_arg_matches(&matches).expect("matches convert");
    assert!(matches!(cli.command,
        Commands::Request(args) if matches!(&args.command,
            request::RequestCommand::List { panel_id } if panel_id == "panel-id")
    ));
    let cli = Cli::try_parse_from(["hiboss", "ss"]).expect("session board accepts no subcommand");
    assert!(matches!(cli.command, Commands::Ss(args) if args.command.is_none()));
}

#[test]
fn grouped_command_parses_box_reference_reads() {
    let matches = grouped_root_command(Cli::command())
        .try_get_matches_from(["hiboss", "box", "latest", "--kind", "image", "--json"])
        .expect("Box reference read parses");
    let cli = Cli::from_arg_matches(&matches).expect("matches convert");
    assert!(matches!(cli.command,
        Commands::Box(args) if matches!(&args.command, box_cmd::BoxCommand::Latest(latest)
            if matches!(&latest.filters.kind, Some(hiboss::box_types::BoxKind::Image)) && latest.output.json)
    ));
}
