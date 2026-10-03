// Verifies onboarding failure boundaries through the built hiboss binary.
// Covers refused invites, name conflicts, rejection, timeout, and bootstrap headers.
// Dependencies: std HTTP mock and shared synthetic onboarding fixtures.

mod onboarding_support;
use onboarding_support::http::{Http, Response};
use onboarding_support::*;
use serde_json::json;
use std::time::{Duration, Instant};

#[test]
fn forbidden_invite_does_not_poll_or_write_credentials() {
    let sandbox = Sandbox::new();
    let server = Http::start(|_| Response::json(403, json!({"error":"invite invalid or expired"})));
    let output = setup(&sandbox, &server.url, &["--profile", "aid"]);
    assert_ne!(output.code, 0);
    assert!(
        output.stderr.to_ascii_lowercase().contains("invite"),
        "{}",
        output.stderr
    );
    assert!(!sandbox.config_file().exists());
    assert_eq!(server.requests().len(), 1);
}

#[test]
fn conflict_reports_names_and_a_distinct_label_without_polling() {
    let sandbox = Sandbox::new();
    let server = Http::start(|_| {
        Response::json(
            409,
            json!({"error":"name conflict", "conflicts":["synthetic-aid@host"]}),
        )
    });
    let output = setup(&sandbox, &server.url, &["--profile", "aid"]);
    assert_ne!(output.code, 0);
    assert!(
        output.stderr.contains("synthetic-aid@host"),
        "{}",
        output.stderr
    );
    assert!(output.stderr.contains("--label"), "{}", output.stderr);
    assert!(!sandbox.config_file().exists());
    assert_eq!(server.requests().len(), 1);
}

#[test]
fn a_distinct_label_is_sent_with_the_grouped_join() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    let output = setup(
        &sandbox,
        &server.url,
        &["--profile", "aid", "--label", "synthetic-second-machine"],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    let requests = server.requests();
    assert_eq!(
        requests[0].body["device"]["label"],
        "synthetic-second-machine"
    );
    assert!(
        requests[0].body["profiles"][0]["name"]
            .as_str()
            .expect("agent name")
            .contains("synthetic-second-machine")
    );
}

#[test]
fn rejected_group_does_not_save_any_profile() {
    let sandbox = Sandbox::new();
    let server = join_server("rejected");
    let output = setup(
        &sandbox,
        &server.url,
        &["--profile", "aid", "--profile", "codex"],
    );
    assert_ne!(output.code, 0);
    assert!(
        output.stderr.to_ascii_lowercase().contains("reject"),
        "{}",
        output.stderr
    );
    assert!(!sandbox.config_file().exists());
    assert!(
        server
            .requests()
            .iter()
            .any(|request| request.path.starts_with("/api/join/status?"))
    );
}

#[test]
fn a_stalled_join_request_obeys_the_ten_second_http_timeout() {
    let sandbox = Sandbox::new();
    let server = Http::start(|_| Response {
        status: 200,
        body: json!({"status":"pending"}),
        delay: Duration::from_secs(11),
    });
    let start = Instant::now();
    let output = setup(&sandbox, &server.url, &["--profile", "aid"]);
    assert_ne!(output.code, 0);
    assert!(start.elapsed() >= Duration::from_secs(9) && start.elapsed() < Duration::from_secs(15));
    assert!(!sandbox.config_file().exists());
    assert_eq!(server.requests().len(), 1);
}

#[test]
fn first_device_bootstrap_sends_the_secret_only_in_the_header() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    let secret = "synthetic-first-device-secret";
    let output = sandbox.run_input(
        &[
            "setup",
            "--server",
            &server.url,
            "--profile",
            "aid",
            "--bootstrap-secret",
            secret,
            "--yes",
        ],
        "",
        &[("NO_PROXY", "127.0.0.1")],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    let requests = server.requests();
    assert_eq!(requests[0].header("x-bootstrap-secret"), Some(secret));
    assert!(!requests[0].body.to_string().contains(secret));
    assert_no_secrets(&output, &[secret, "synthetic-key-aid"]);
    assert_private_config(&sandbox);
}

#[test]
fn bootstrap_environment_secret_is_used_without_an_invite_prompt() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    let secret = "synthetic-env-bootstrap-secret";
    let output = sandbox.run_input(
        &[
            "setup",
            "--server",
            &server.url,
            "--profile",
            "aid",
            "--yes",
        ],
        "",
        &[
            ("NO_PROXY", "127.0.0.1"),
            ("HIBOSS_BOOTSTRAP_SECRET", secret),
        ],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert_eq!(
        server.requests()[0].header("x-bootstrap-secret"),
        Some(secret)
    );
    assert_no_secrets(&output, &[secret, "synthetic-key-aid"]);
}

#[test]
fn check_fails_when_one_configured_identity_is_unauthorized() {
    let sandbox = Sandbox::new();
    let server = Http::start(|_| Response::json(403, json!({"error":"forbidden"})));
    existing_config(&sandbox, &server.url);
    let before = sandbox.read_config();
    let output = sandbox.run_input(&["setup", "--check"], "", &[("NO_PROXY", "127.0.0.1")]);
    assert_ne!(output.code, 0);
    assert_eq!(sandbox.read_config(), before);
    let requests = server.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(
        (&*requests[0].method, &*requests[0].path),
        ("GET", "/api/agents/me")
    );
    assert_no_secrets(&output, &[EXISTING_KEY]);
}
