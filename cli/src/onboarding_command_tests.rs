// Checks machine onboarding argument parsing and retained local setup subcommands.
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
}

#[test]
fn local_setup_subcommands_still_parse() {
    for command in ["hooks", "agents"] {
        let cli = Cli::try_parse_from(["hiboss", "setup", command]).expect("local setup parses");
        let Commands::Setup(args) = cli.command else {
            panic!("setup expected");
        };
        assert!(args.command.is_some());
    }
}

#[test]
fn removed_boss_channel_commands_and_flags_are_rejected() {
    for path in [
        "channel list",
        "forward message-id discord",
        "route list",
        "setup telegram",
        "setup telegram-commands",
        "setup discord",
        "send hello --channel telegram",
        "ask hello --channel discord",
        "agent config --channel-routing normal=discord",
        "boss update boss-id --telegram-user-id 123",
        "boss update boss-id --discord-user-id 123",
        "config set channel discord",
    ] {
        let args = std::iter::once("hiboss").chain(path.split_whitespace());
        assert!(Cli::try_parse_from(args).is_err(), "{path}");
    }
    assert!(Cli::try_parse_from(["hiboss", "react", "message-id", "👍"]).is_ok());
    assert!(Cli::try_parse_from(["hiboss", "integration", "list"]).is_ok());
}

#[test]
fn obsolete_initialization_and_boss_creation_commands_are_rejected() {
    assert!(Cli::try_parse_from(["hiboss", "init", "https://hiboss.example"]).is_err());
    assert!(Cli::try_parse_from(["hiboss", "boss", "add", "Synthetic Boss"]).is_err());
    assert!(Cli::try_parse_from(["hiboss", "device", "invite"]).is_ok());
}
