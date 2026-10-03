// Exercises invitation redemption, one-time key persistence, and concurrent setup safety.
// Drives the built binary against a synthetic local HTTP server on the build host.
// Dependencies: shared onboarding fixtures, std threads, channels, and serde_json.

mod onboarding_support;
use onboarding_support::{
    http::{Http, Response},
    *,
};
use serde_json::{Value, json};
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    time::Duration,
};

#[test]
fn minted_invite_enrolls_a_second_machine_and_delivers_keys_once() {
    let inviter = Sandbox::new();
    let machine = Sandbox::new();
    let server = invite_and_join_server();
    existing_config(&inviter, &server.url);
    let output = inviter.run_input(
        &["device", "invite", "--json", "--copy"],
        "",
        &[("NO_PROXY", "127.0.0.1"), ("PATH", "")],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    let invite: Value = serde_json::from_str(&output.stdout).expect("invite JSON");
    assert_eq!(invite["invite"], INVITE);
    assert!(
        invite["prompt"]
            .as_str()
            .expect("prompt")
            .contains(&server.url)
    );
    assert!(output.stderr.contains("Clipboard unavailable"));
    assert_no_secrets(&output, &[EXISTING_KEY]);
    let enrolled = setup(
        &machine,
        &server.url,
        &["--profile", "aid", "--profile", "codex"],
    );
    assert_eq!(enrolled.code, 0, "{}", enrolled.stderr);
    let config = saved_config(&machine);
    for name in ["aid", "codex"] {
        assert_eq!(
            config["profiles"][name]["key"],
            format!("synthetic-key-{name}")
        );
    }
    assert_private_config(&machine);
    assert_no_secrets(&enrolled, &["synthetic-key-aid", "synthetic-key-codex"]);
    assert_eq!(server.requests().len(), 3);
}

fn invite_and_join_server() -> Http {
    let requested = Arc::new(Mutex::new(json!([])));
    let profiles = requested.clone();
    let delivered = AtomicBool::new(false);
    Http::start(move |request| match request.path.as_str() {
        "/api/devices/invites" => Response::json(
            201,
            json!({"invite":INVITE, "expires_at":"2099-01-01T00:00:00Z", "inviter_label":"synthetic-host"}),
        ),
        "/api/join" => {
            assert_eq!(request.body["invite"], INVITE);
            *profiles.lock().expect("profiles") = request.body["profiles"].clone();
            Response::json(
                201,
                json!({"request_id":"synthetic-request", "poll_token":"synthetic-poll", "status":"pending", "verification_code":"123456"}),
            )
        }
        _ if request.path.starts_with("/api/join/status?") => {
            assert!(
                !delivered.swap(true, Ordering::SeqCst),
                "keys must be retrieved only once"
            );
            Response::json(
                200,
                approval("approved", &profiles.lock().expect("profiles")),
            )
        }
        _ => Response::json(404, json!({"error":"unexpected endpoint"})),
    })
}

#[test]
fn simultaneous_setup_cannot_submit_a_second_request_or_drop_a_key() {
    let sandbox = Sandbox::new();
    let (sent, received) = mpsc::channel();
    let requested = Arc::new(Mutex::new(json!([])));
    let profiles = requested.clone();
    let server = Http::start(move |request| {
        if request.path == "/api/join" {
            *profiles.lock().expect("profiles") = request.body["profiles"].clone();
            sent.send(()).expect("join event");
            Response::json(
                201,
                json!({"request_id":"synthetic-request", "poll_token":"synthetic-poll", "status":"pending", "verification_code":"123456"}),
            )
        } else {
            Response::json(
                200,
                approval("approved", &profiles.lock().expect("profiles")),
            )
        }
    });
    std::thread::scope(|scope| {
        let first = scope.spawn(|| setup(&sandbox, &server.url, &["--profile", "aid"]));
        received
            .recv_timeout(Duration::from_secs(5))
            .expect("first join started");
        let second = setup(&sandbox, &server.url, &["--profile", "codex"]);
        assert_ne!(second.code, 0);
        assert!(second.stderr.contains("Another setup is running"));
        assert_eq!(first.join().expect("first setup").code, 0);
    });
    assert_eq!(
        saved_config(&sandbox)["profiles"]["aid"]["key"],
        "synthetic-key-aid"
    );
    assert_one_grouped_join(&server.requests(), 1);
}

#[test]
fn path_detection_uses_config_server_and_skips_existing_profiles_without_prompting() {
    use std::{fs, os::unix::fs::PermissionsExt};
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    existing_config(&sandbox, &server.url);
    let bin = sandbox.home.join("bin");
    fs::create_dir_all(&bin).expect("fake runtime bin");
    for name in ["claude", "codex", "gemini", "aid"] {
        let executable = bin.join(name);
        fs::write(&executable, "#!/bin/sh\nexit 0\n").expect("fake executable");
        fs::set_permissions(executable, fs::Permissions::from_mode(0o755))
            .expect("executable mode");
    }
    let output = sandbox.run_input(
        &["setup", "--yes"],
        "",
        &[
            ("NO_PROXY", "127.0.0.1"),
            ("PATH", bin.to_str().expect("bin path")),
            ("USER", "Test User"),
        ],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert!(output.stdout.contains("Skipping profile aid"));
    assert!(!output.stderr.contains("Continue?"));
    let config = saved_config(&sandbox);
    assert_eq!(config["profiles"].as_object().expect("profiles").len(), 4);
    assert_eq!(config["default_profile"], "aid");
    assert_eq!(config["profiles"]["aid"]["key"], EXISTING_KEY);
    assert!(
        config["profiles"]["codex"]["name"]
            .as_str()
            .expect("name")
            .starts_with("Test-User-codex@")
    );
    assert_one_grouped_join(&server.requests(), 3);
}

#[test]
fn immediate_bootstrap_approval_saves_keys_without_polling() {
    let sandbox = Sandbox::new();
    let server = Http::start(|request| {
        let mut response = approval("approved", &request.body["profiles"]);
        response["request_id"] = json!("synthetic-request");
        response["poll_token"] = json!("synthetic-poll");
        Response::json(201, response)
    });
    let output = sandbox.run_input(
        &[
            "setup",
            "--server",
            &server.url,
            "--bootstrap-secret",
            "synthetic-secret",
            "--profile",
            "aid",
            "--yes",
        ],
        "",
        &[("NO_PROXY", "127.0.0.1")],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert_eq!(
        saved_config(&sandbox)["profiles"]["aid"]["key"],
        "synthetic-key-aid"
    );
    assert!(!output.stdout.contains("VERIFICATION CODE"));
    assert_eq!(server.requests().len(), 1);
    assert_no_secrets(&output, &["synthetic-secret", "synthetic-key-aid"]);
}
