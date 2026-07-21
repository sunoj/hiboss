// Purpose: Verify the canonical repeatable option and action CLI contract.
// Covers comma preservation, legacy migration guidance, conflicts, and limits.
// Dependencies: clap and AskArgs choice payload validation.

use crate::commands::ask::AskArgs;
use clap::Parser;

#[derive(Debug, Parser)]
struct AskCommand {
    #[command(flatten)]
    args: AskArgs,
}

#[test]
fn repeated_options_preserve_commas() {
    let command = parse(&[
        "--option",
        "Delete sccache (10G,rebuildable,recommended)",
        "--option",
        "Run cleanup",
        "Choose",
    ]);

    let payload = command.args.choice_payload().expect("valid options");
    assert_eq!(
        payload.options,
        Some(vec![
            "Delete sccache (10G,rebuildable,recommended)".to_owned(),
            "Run cleanup".to_owned(),
        ])
    );
}

#[test]
fn repeated_actions_split_only_on_first_equals_sign() {
    let command = parse(&[
        "--action",
        "Approve, recommended=tools/cleanup --filter=a,b",
        "Choose",
    ]);

    let payload = command.args.choice_payload().expect("valid action");
    assert_eq!(
        payload.options,
        Some(vec!["Approve, recommended".to_owned()])
    );
    assert_eq!(
        payload
            .actions
            .get("Approve, recommended")
            .and_then(|value| value.as_str()),
        Some("tools/cleanup --filter=a,b")
    );
}

#[test]
fn legacy_plural_flags_explain_the_new_repeatable_syntax() {
    let options_error = AskCommand::try_parse_from(["test", "--options", "A,B", "Choose"])
        .expect_err("plural options must fail")
        .to_string();
    let actions_error = AskCommand::try_parse_from(["test", "--actions", "A=run", "Choose"])
        .expect_err("plural actions must fail")
        .to_string();

    assert!(options_error.contains("repeat --option once per choice"));
    assert!(options_error.contains("comma-separated choices are ambiguous"));
    assert!(actions_error.contains("repeat --action once per LABEL=COMMAND pair"));
}

#[test]
fn options_and_actions_conflict() {
    let result = AskCommand::try_parse_from([
        "test",
        "--option",
        "Wait",
        "--action",
        "Approve=deploy",
        "Choose",
    ]);
    assert!(result.is_err());
}

#[test]
fn more_than_five_options_are_rejected() {
    let command = parse(&[
        "--option", "1", "--option", "2", "--option", "3", "--option", "4", "--option", "5",
        "--option", "6", "Choose",
    ]);

    let error = command
        .args
        .choice_payload()
        .expect_err("six options must fail");
    assert!(error.to_string().contains("at most 5"));
}

#[test]
fn default_must_match_an_option_label() {
    let command = parse(&["--option", "A", "--option", "B", "--default", "A", "Choose"]);
    let payload = command.args.choice_payload().expect("valid default");
    assert_eq!(payload.default_option, Some("A".to_owned()));
}

#[test]
fn default_unknown_label_is_rejected() {
    let command = parse(&["--option", "A", "--option", "B", "--default", "Z", "Choose"]);
    let error = command
        .args
        .choice_payload()
        .expect_err("unknown default must fail");
    assert!(error.to_string().contains("--default 'Z'"));
}

#[test]
fn default_without_options_is_rejected() {
    let command = parse(&["--default", "A", "Choose"]);
    let error = command
        .args
        .choice_payload()
        .expect_err("default without options must fail");
    assert!(error.to_string().contains("--default 'A'"));
}

#[test]
fn default_matches_action_label() {
    let command = parse(&[
        "--action",
        "Approve=deploy",
        "--action",
        "Reject=echo no",
        "--default",
        "Approve",
        "Choose",
    ]);
    let payload = command.args.choice_payload().expect("valid action default");
    assert_eq!(payload.default_option, Some("Approve".to_owned()));
}

fn parse(arguments: &[&str]) -> AskCommand {
    AskCommand::try_parse_from(std::iter::once("test").chain(arguments.iter().copied()))
        .expect("arguments should parse")
}
