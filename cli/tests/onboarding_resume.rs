// Verifies that a pending join request survives the setup process through the built binary.
// Covers timeout then resume, rejection, already-delivered keys, 404, and --abandon.
// Dependencies: std HTTP mock and shared synthetic onboarding fixtures.

mod onboarding_support;
use onboarding_support::http::{Http, Request, Response};
use onboarding_support::*;
use serde_json::{Value, json};
use std::path::PathBuf;

const LOOPBACK: &[(&str, &str)] = &[("NO_PROXY", "127.0.0.1")];

fn pending_file(sandbox: &Sandbox) -> PathBuf {
    sandbox
        .config_file()
        .with_file_name("pending-enrollment.json")
}

/// Sends the join, then exits on the one-second wait before the first poll.
fn start_and_time_out(sandbox: &Sandbox, server: &str) {
    let output = setup(sandbox, server, &["--profile", "aid", "--wait", "1"]);
    assert_ne!(output.code, 0);
    assert!(
        output
            .stderr
            .contains("Still waiting for approval; run `hiboss setup` again"),
        "{}",
        output.stderr
    );
    assert!(pending_file(sandbox).is_file());
}

fn resume(sandbox: &Sandbox) -> Outcome {
    sandbox.run_input(&["setup", "--yes"], "", LOOPBACK)
}

fn joins(requests: &[Request]) -> usize {
    requests
        .iter()
        .filter(|request| request.method == "POST" && request.path == "/api/join")
        .count()
}

/// Accepts the join as pending and answers every status poll with `status`.
fn status_server(status: u16, body: Value) -> Http {
    Http::start(move |request| {
        if request.method == "POST" && request.path == "/api/join" {
            Response::json(
                201,
                json!({"status":"pending", "request_id":"synthetic-request",
                    "poll_token":"synthetic-poll", "verification_code":"123456"}),
            )
        } else {
            Response::json(status, body.clone())
        }
    })
}

#[test]
fn timeout_keeps_a_private_keyless_file_and_a_rerun_saves_the_approval() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    start_and_time_out(&sandbox, &server.url);
    let body = std::fs::read_to_string(pending_file(&sandbox)).expect("pending file");
    let saved: Value = serde_json::from_str(&body).expect("pending json");
    assert_eq!(saved["server"], server.url.as_str());
    assert_eq!(saved["poll_token"], "synthetic-poll");
    assert_eq!(saved["verification_code"], "123456");
    assert_eq!(saved["profiles"][0]["profile"], "aid");
    assert!(saved["created_at"].as_str().is_some_and(|at| !at.is_empty()));
    assert!(!body.contains("synthetic-key") && !body.contains(INVITE));
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(pending_file(&sandbox))
            .expect("pending mode")
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }
    let output = sandbox.run_input(&["setup", "--invite", INVITE, "--yes"], "", LOOPBACK);
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert!(output.stdout.contains("Resuming the pending request from"));
    assert!(output.stdout.contains("VERIFICATION CODE: 123456"));
    assert!(output.stderr.contains("ignoring --invite"), "{}", output.stderr);
    assert_no_secrets(&output, &["synthetic-key-aid"]);
    assert!(!pending_file(&sandbox).exists());
    let config = saved_config(&sandbox);
    assert_eq!(config["profiles"]["aid"]["key"], "synthetic-key-aid");
    assert_private_config(&sandbox);
    assert_eq!(joins(&server.requests()), 1);
}

#[test]
fn resuming_a_rejected_request_removes_the_file_and_saves_nothing() {
    let sandbox = Sandbox::new();
    let server = join_server("rejected");
    start_and_time_out(&sandbox, &server.url);
    let output = resume(&sandbox);
    assert_ne!(output.code, 0);
    assert!(output.stderr.contains("rejected"), "{}", output.stderr);
    assert!(!pending_file(&sandbox).exists());
    assert!(!sandbox.config_file().exists());
    assert_eq!(joins(&server.requests()), 1);
}

#[test]
fn resuming_after_keys_were_delivered_removes_the_file_and_fails() {
    let sandbox = Sandbox::new();
    let server = status_server(
        200,
        json!({"status":"approved", "request_id":"synthetic-request", "delivered":true}),
    );
    start_and_time_out(&sandbox, &server.url);
    let output = resume(&sandbox);
    assert_ne!(output.code, 0);
    assert!(
        output.stderr.contains("already delivered"),
        "{}",
        output.stderr
    );
    assert!(!pending_file(&sandbox).exists());
    assert!(!sandbox.config_file().exists());
    assert_eq!(joins(&server.requests()), 1);
}

#[test]
fn resuming_an_unknown_request_removes_the_file_and_fails() {
    let sandbox = Sandbox::new();
    let server = status_server(404, json!({"error":"not found"}));
    start_and_time_out(&sandbox, &server.url);
    let output = resume(&sandbox);
    assert_ne!(output.code, 0);
    assert!(
        output.stderr.contains("no longer knows"),
        "{}",
        output.stderr
    );
    assert!(!pending_file(&sandbox).exists());
    assert_eq!(joins(&server.requests()), 1);
}

#[test]
fn abandon_deletes_the_pending_file_beside_hiboss_config_without_polling() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    let config = sandbox.home.join("custom").join("config.json");
    let config = config.to_str().expect("config path");
    let custom = [("NO_PROXY", "127.0.0.1"), ("HIBOSS_CONFIG", config)];
    let mut args = profile_arguments(&server.url, &["aid"]);
    args.extend(["--wait", "1"]);
    let output = sandbox.run_input(&args, "", &custom);
    assert_ne!(output.code, 0);
    let pending = sandbox.home.join("custom").join("pending-enrollment.json");
    assert!(pending.is_file());
    let output = sandbox.run_input(&["setup", "--abandon"], "", &custom);
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert!(output.stdout.contains("Abandoned"), "{}", output.stdout);
    assert!(!pending.exists());
    let requests = server.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(joins(&requests), 1);
}
