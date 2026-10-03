// Checks machine onboarding argument parsing and retained integration subcommands.
// Exports binary parser tests for setup flags and removed entry points.
// Dependencies: the binary's Clap definitions and setup command contracts.

use super::*;

#[test]
fn bare_setup_parses_grouped_onboarding_flags_without_a_subcommand() {
    let cli = Cli::try_parse_from([
        "hiboss",
        "setup",
        "--server",
        "https://hiboss.example",
        "--invite",
        "synthetic-invite",
        "--profile",
        "claude",
        "--profile",
        "codex",
        "--label",
        "laptop",
        "--bootstrap-secret",
        "synthetic-bootstrap",
        "--yes",
        "--check",
    ])
    .expect("onboarding flags parse");
    let Commands::Setup(args) = cli.command else {
        panic!("setup command expected");
    };
    assert!(args.command.is_none());
    assert_eq!(args.server.as_deref(), Some("https://hiboss.example"));
    assert_eq!(args.invite.as_deref(), Some("synthetic-invite"));
    assert_eq!(args.profile, ["claude", "codex"]);
    assert_eq!(args.label.as_deref(), Some("laptop"));
    assert_eq!(
        args.bootstrap_secret.as_deref(),
        Some("synthetic-bootstrap")
    );
    assert!(args.yes && args.check);
    assert!(!setup::needs_client(&args));
}

#[test]
fn integration_setup_subcommands_keep_their_client_requirements() {
    for (command, needs_client) in [
        ("hooks", false),
        ("agents", false),
        ("telegram", true),
        ("telegram-commands", true),
        ("discord", true),
    ] {
        let cli = Cli::try_parse_from(["hiboss", "setup", command]).expect("integration parses");
        let Commands::Setup(args) = cli.command else {
            panic!("setup expected");
        };
        assert!(args.command.is_some());
        assert_eq!(setup::needs_client(&args), needs_client);
    }
}

#[test]
fn obsolete_initialization_and_boss_creation_commands_are_rejected() {
    assert!(Cli::try_parse_from(["hiboss", "init", "https://hiboss.example"]).is_err());
    assert!(Cli::try_parse_from(["hiboss", "boss", "add", "Synthetic Boss"]).is_err());
    assert!(Cli::try_parse_from(["hiboss", "device", "invite"]).is_ok());
}
