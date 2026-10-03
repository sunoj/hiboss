// Exercises machine onboarding through the built hiboss binary with mock HTTP.
// Covers grouped approval, prompts, saved profile preservation, and identity checks.
// Dependencies: isolated sandbox and synthetic onboarding HTTP fixtures.

mod onboarding_support;
use onboarding_support::http::{Http, Response};
use onboarding_support::*;
use serde_json::json;

#[test]
fn one_grouped_approval_persists_every_runtime_profile_without_printing_keys() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    let args = profile_arguments(&server.url, &["claude", "codex", "gemini", "aid"]);
    let output = sandbox.run_input(&args, "", &[("NO_PROXY", "127.0.0.1")]);
    assert_eq!(output.code, 0, "{}", output.stderr);
    let config = saved_config(&sandbox);
    assert_eq!(config["version"], 2);
    assert_eq!(config["device_id"], "synthetic-device");
    assert_eq!(config["server"], server.url);
    for profile in ["claude", "codex", "gemini", "aid"] {
        let key = format!("synthetic-key-{profile}");
        assert_eq!(config["profiles"][profile]["key"], key);
        assert_eq!(
            config["profiles"][profile]["agent_id"],
            format!("synthetic-agent-{profile}")
        );
        assert_no_secrets(&output, &[&key]);
    }
    assert_private_config(&sandbox);
    let requests = server.requests();
    assert_one_grouped_join(&requests, 4);
    assert!(
        requests
            .iter()
            .any(|request| request.path.starts_with("/api/join/status?"))
    );
    assert!(requests[0].header("authorization").is_none());
    assert_eq!(requests[0].body["invite"], INVITE);
    assert!(
        output.stdout.contains("123456"),
        "verification code is displayed"
    );
}

#[test]
fn missing_server_reports_the_required_flag_without_prompting() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    let output = sandbox.run_input(
        &["setup", "--profile", "aid", "--yes"],
        "",
        &[("NO_PROXY", "127.0.0.1")],
    );
    assert_ne!(output.code, 0);
    assert!(output.stderr.contains("--server <url>"));
    assert!(!output.stderr.contains("Continue?"));
    assert_no_secrets(&output, &["synthetic-key-aid"]);
    assert!(!sandbox.config_file().exists());
    assert!(server.requests().is_empty());
}

#[test]
fn adding_a_profile_skips_existing_profiles_and_preserves_their_credentials() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    existing_config(&sandbox, &server.url);
    let output = setup(
        &sandbox,
        &server.url,
        &["--profile", "aid", "--profile", "codex"],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    let config = saved_config(&sandbox);
    assert_eq!(config["profiles"]["aid"]["key"], EXISTING_KEY);
    assert_eq!(
        config["profiles"]["aid"]["agent_id"],
        "synthetic-existing-agent"
    );
    assert_eq!(config["profiles"]["aid"]["name"], "synthetic-aid@old-host");
    assert_eq!(config["profiles"]["codex"]["key"], "synthetic-key-codex");
    assert_eq!(config["channel"], "discord");
    let requests = server.requests();
    assert_eq!(
        requests[0].body["profiles"]
            .as_array()
            .expect("profiles")
            .len(),
        1
    );
    assert_eq!(requests[0].body["profiles"][0]["profile"], "codex");
    assert_eq!(requests[0].header("x-device-proof"), Some(EXISTING_KEY));
    assert_no_secrets(&output, &[EXISTING_KEY, "synthetic-key-codex"]);
    assert_private_config(&sandbox);
}

#[test]
fn rerunning_setup_for_existing_profiles_does_not_join_or_replace_keys() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    existing_config(&sandbox, &server.url);
    let before = saved_config(&sandbox);
    let output = setup(&sandbox, &server.url, &["--profile", "aid"]);
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert_eq!(saved_config(&sandbox), before);
    assert!(server.requests().is_empty());
    assert_no_secrets(&output, &[EXISTING_KEY]);
}

#[test]
fn check_gets_each_configured_identity_with_its_profile_key_and_server_override() {
    let sandbox = Sandbox::new();
    let first = Http::start(|_| {
        Response::json(
            200,
            json!({"id":"synthetic-existing-agent", "name":"aid@host"}),
        )
    });
    let second =
        Http::start(|_| Response::json(200, json!({"id":"synthetic-codex", "name":"codex@host"})));
    existing_config(&sandbox, &first.url);
    let mut config = saved_config(&sandbox);
    config["profiles"]["codex"] = json!({"server":second.url, "key":"synthetic-codex-check-key", "agent_id":"synthetic-codex", "name":"codex@host"});
    sandbox.write_config(&config.to_string());
    let before = sandbox.read_config();
    let output = sandbox.run_input(&["setup", "--check"], "", &[("NO_PROXY", "127.0.0.1")]);
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert_eq!(sandbox.read_config(), before);
    for (server, key) in [(first, EXISTING_KEY), (second, "synthetic-codex-check-key")] {
        let requests = server.requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(
            (&*requests[0].method, &*requests[0].path),
            ("GET", "/api/agents/me")
        );
        assert_eq!(
            requests[0].header("authorization"),
            Some(format!("Bearer {key}").as_str())
        );
    }
    assert_no_secrets(&output, &[EXISTING_KEY, "synthetic-codex-check-key"]);
}
