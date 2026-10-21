// Exercises first-boss pairing output and enrollment through the built CLI.
// Uses isolated config and synthetic HTTP responses; credentials stay in memory.
mod onboarding_support;
use onboarding_support::http::{Http, Response};
use onboarding_support::*;
use serde_json::json;

#[test]
fn first_install_prints_pairing_link_code_expiry_and_qr_without_secret() {
    let sandbox = Sandbox::new();
    let server = Http::start(|request| match request.path.as_str() {
        "/api/bootstrap/boss" => Response::json(
            201,
            json!({
                "code":"ABCD1234", "expires_at":"2030-01-01T00:00:00Z"
            }),
        ),
        "/api/join" => Response::json(
            201,
            json!({
                "request_id":"request", "poll_token":"poll", "status":"rejected"
            }),
        ),
        _ => Response::json(404, json!({})),
    });
    let output = sandbox.run_input(
        &[
            "setup",
            "--server",
            &server.url,
            "--profile",
            "aid",
            "--yes",
            "--bootstrap-secret",
            "synthetic-install-secret",
        ],
        "",
        &[("NO_PROXY", "127.0.0.1")],
    );
    let link = output
        .stdout
        .lines()
        .find(|line| line.starts_with("hiboss://pair?"))
        .expect("pairing link");
    let parsed = reqwest::Url::parse(link).expect("valid pairing link");
    let parameters: std::collections::HashMap<_, _> = parsed.query_pairs().collect();
    assert_eq!(
        parameters.get("server").map(|value| value.as_ref()),
        Some(server.url.as_str())
    );
    assert_eq!(
        parameters.get("code").map(|value| value.as_ref()),
        Some("ABCD1234")
    );
    assert!(output.stdout.contains("2030-01-01T00:00:00Z"));
    assert!(output.stdout.contains('█'));
    assert!(output.stdout.contains(
        "Scan with the HiBoss iPhone app, or open HiBoss on the Mac and choose Pair with code."
    ));
    assert_no_secrets(&output, &["synthetic-install-secret"]);
    let requests = server.requests();
    assert_eq!(requests[0].path, "/api/bootstrap/boss");
    assert_eq!(
        requests[0].header("x-bootstrap-secret"),
        Some("synthetic-install-secret")
    );
    assert_eq!(requests[1].path, "/api/join");
}

#[test]
fn existing_boss_continues_enrollment_with_environment_secret_and_explicit_name() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    let output = sandbox.run_input(
        &[
            "setup",
            "--server",
            &server.url,
            "--boss-name",
            "Synthetic Boss",
            "--profile",
            "aid",
            "--yes",
        ],
        "",
        &[
            ("NO_PROXY", "127.0.0.1"),
            ("HIBOSS_BOOTSTRAP_SECRET", "synthetic-env-secret"),
        ],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert_no_secrets(&output, &["synthetic-env-secret", "synthetic-key-aid"]);
    let requests = server.requests();
    assert_eq!(requests[0].body["name"], "Synthetic Boss");
    assert_eq!(
        requests[0].header("x-bootstrap-secret"),
        Some("synthetic-env-secret")
    );
    assert_eq!(requests[1].path, "/api/join");
}

#[test]
fn bootstrap_error_does_not_echo_response_credentials_or_continue_join() {
    let sandbox = Sandbox::new();
    let server =
        Http::start(|_| Response::json(401, json!({"error":"synthetic-reflected-secret"})));
    let output = sandbox.run_input(
        &[
            "setup",
            "--server",
            &server.url,
            "--bootstrap-secret",
            "synthetic-reflected-secret",
            "--profile",
            "aid",
            "--yes",
        ],
        "",
        &[("NO_PROXY", "127.0.0.1")],
    );
    assert_ne!(output.code, 0);
    assert_no_secrets(&output, &["synthetic-reflected-secret"]);
    assert_eq!(server.requests().len(), 1);
}
