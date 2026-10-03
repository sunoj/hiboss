// Shared synthetic fixtures for built-binary machine onboarding tests.
// Exports mock join replies, sandbox access, and config assertions.
// Dependencies: std HTTP fixture, serde_json, and the isolated CLI test sandbox.

#![allow(dead_code)]
pub mod http;
#[path = "../cli_ux_support/mod.rs"]
mod sandbox;
use http::{Http, Response};
pub use sandbox::{Outcome, Sandbox};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};

pub const INVITE: &str = "hb_inv_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
pub const EXISTING_KEY: &str = "synthetic-existing-profile-key";

pub fn join_server(status: &str) -> Http {
    let status = status.to_owned();
    let profiles: Arc<Mutex<Value>> = Arc::new(Mutex::new(json!([])));
    let device: Arc<Mutex<String>> = Arc::new(Mutex::new("synthetic-device".into()));
    Http::start(move |request| {
        if request.method == "POST" && request.path == "/api/join" {
            *profiles.lock().expect("profiles") = request.body["profiles"].clone();
            if request.header("x-device-proof").is_some() {
                *device.lock().expect("device") = "synthetic-existing-device".into();
            }
            Response::json(
                201,
                json!({"status":"pending", "request_id":"synthetic-request", "poll_token":"synthetic-poll", "verification_code":"123456"}),
            )
        } else if request.path.starts_with("/api/join/status?") {
            let requested = profiles.lock().expect("profiles");
            let mut response = approval(&status, &requested);
            response["device_id"] = json!(*device.lock().expect("device"));
            Response::json(200, response)
        } else if request.path == "/api/agents/me" {
            Response::json(
                200,
                json!({"id":"synthetic-agent", "name":"synthetic-name"}),
            )
        } else {
            Response::json(404, json!({"error":"unexpected mock endpoint"}))
        }
    })
}

pub fn approval(status: &str, requested: &Value) -> Value {
    let profiles: Vec<Value> = requested.as_array().expect("requested profiles").iter()
        .map(|profile| json!({
            "profile": profile["profile"], "name": profile["name"],
            "agent_id": format!("synthetic-agent-{}", profile["profile"].as_str().expect("profile")),
            "key": format!("synthetic-key-{}", profile["profile"].as_str().expect("profile"))
        })).collect();
    json!({"status":status, "device_id":"synthetic-device", "profiles":profiles})
}

pub fn saved_config(sandbox: &Sandbox) -> Value {
    serde_json::from_str(&sandbox.read_config()).expect("saved config")
}

pub fn existing_config(sandbox: &Sandbox, server: &str) {
    sandbox.write_config(&json!({"version":2, "server":server, "device_id":"synthetic-existing-device",
        "default_profile":"aid", "channel":"discord", "profiles":{
            "aid":{"key":EXISTING_KEY, "agent_id":"synthetic-existing-agent", "name":"synthetic-aid@old-host"}
        }}).to_string());
}

pub fn setup(sandbox: &Sandbox, server: &str, extra: &[&str]) -> Outcome {
    let mut args = vec!["setup", "--server", server, "--invite", INVITE, "--yes"];
    args.extend_from_slice(extra);
    sandbox.run_input(&args, "", &[("NO_PROXY", "127.0.0.1")])
}

pub fn profile_arguments<'a>(server: &'a str, profiles: &[&'a str]) -> Vec<&'a str> {
    let mut args = vec!["setup", "--server", server, "--invite", INVITE, "--yes"];
    for profile in profiles {
        args.extend(["--profile", *profile]);
    }
    args
}

pub fn assert_one_grouped_join(requests: &[http::Request], profiles: usize) {
    let joins: Vec<&http::Request> = requests
        .iter()
        .filter(|request| request.method == "POST" && request.path == "/api/join")
        .collect();
    assert_eq!(joins.len(), 1);
    assert_eq!(
        joins[0].body["profiles"]
            .as_array()
            .expect("profiles")
            .len(),
        profiles
    );
}

pub fn assert_private_config(sandbox: &Sandbox) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            std::fs::metadata(sandbox.config_file())
                .expect("config mode")
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }
}

pub fn assert_no_secrets(output: &Outcome, secrets: &[&str]) {
    for secret in secrets {
        assert!(
            !output.stdout.contains(secret) && !output.stderr.contains(secret),
            "credential was exposed"
        );
    }
}
