// Verifies description validation precedes all ask attachment uploads.
// Depends on the parent ask request builder and clap parsing.

use super::*;
use clap::Parser;

#[derive(Parser)]
struct Command {
    #[command(flatten)]
    args: AskArgs,
}

#[tokio::test]
async fn invalid_descriptions_fail_before_option_or_file_uploads() {
    let args = Command::parse_from([
        "ask",
        "--option",
        "A",
        "--option-description",
        "B=text",
        "--option-image",
        "A=/missing.png",
        "--file",
        "/missing.txt",
        "Choose",
    ])
    .args;
    let choices = args.choice_payload().expect("valid choices");
    let client = HiBossClient::new("http://127.0.0.1:1", "test-key");
    let error = prepare_request(&args, &client, &choices)
        .await
        .err()
        .expect("invalid description");
    assert!(error.to_string().contains("option description label"));
}
