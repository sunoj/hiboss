// Purpose: Verify the canonical repeatable option and action CLI contract.
// Covers comma preservation, legacy migration guidance, conflicts, and limits.
// Dependencies: clap and AskArgs choice payload validation.

use crate::commands::ask::AskArgs;
use crate::commands::ask_media::{is_remote_url, parse_option_images, validate_option_image_labels};
use clap::Parser;

#[derive(Debug, Parser)]
struct AskCommand {
    #[command(flatten)]
    args: AskArgs,
}

#[test]
fn json_output_is_opt_in() {
    assert!(parse(&["--json", "Choose"]).args.json);
    assert!(!parse(&["Choose"]).args.json);
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

#[test]
fn option_image_flag_matches_an_option_label() {
    let command = parse(&[
        "--option",
        "压缩文案",
        "--option-image",
        "压缩文案=./after.png",
        "--option",
        "保持不动",
        "Choose",
    ]);
    assert_eq!(command.args.option_images, vec!["压缩文案=./after.png"]);
    let choices = command.args.choice_payload().expect("valid options");
    let images = parse_option_images(&command.args.option_images).expect("valid option image");
    assert!(validate_option_image_labels(&images, &choices).is_ok());
}

#[test]
fn option_image_flag_matches_an_action_label() {
    let command = parse(&[
        "--action",
        "Approve=deploy",
        "--option-image",
        "Approve=./ok.png",
        "Choose",
    ]);
    let choices = command.args.choice_payload().expect("valid action");
    let images = parse_option_images(&command.args.option_images).expect("valid option image");
    assert!(validate_option_image_labels(&images, &choices).is_ok());
}

#[test]
fn option_image_with_unknown_label_is_rejected() {
    let command = parse(&[
        "--option",
        "A",
        "--option-image",
        "Z=./z.png",
        "Choose",
    ]);
    let choices = command.args.choice_payload().expect("valid options");
    let images = parse_option_images(&command.args.option_images).expect("valid option image");
    let error = validate_option_image_labels(&images, &choices).expect_err("unknown label fails");
    assert!(error.to_string().contains("'Z'"));
}

#[test]
fn option_image_without_any_choice_is_rejected() {
    let command = parse(&["--option-image", "A=./a.png", "Choose"]);
    let choices = command.args.choice_payload().expect("no choices");
    let images = parse_option_images(&command.args.option_images).expect("valid option image");
    assert!(validate_option_image_labels(&images, &choices).is_err());
}

#[test]
fn option_image_splits_at_the_first_equals_sign() {
    let command = parse(&[
        "--option",
        "A",
        "--option-image",
        "A=https://x/api/attachments/a.png?token=abc=def",
        "Choose",
    ]);
    let images = parse_option_images(&command.args.option_images).expect("valid option image");
    assert_eq!(images[0].label, "A");
    assert_eq!(images[0].source, "https://x/api/attachments/a.png?token=abc=def");
}

#[test]
fn option_image_urls_pass_through_and_paths_do_not() {
    assert!(is_remote_url("https://x/api/attachments/a.png"));
    assert!(is_remote_url("http://x/api/attachments/a.png"));
    assert!(!is_remote_url("./after.png"));
    assert!(!is_remote_url("/tmp/after.png"));
}

fn parse(arguments: &[&str]) -> AskCommand {
    AskCommand::try_parse_from(std::iter::once("test").chain(arguments.iter().copied()))
        .expect("arguments should parse")
}
