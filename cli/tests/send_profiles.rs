// Checks missing-Claude-session warnings without interrupting message delivery.
// Covers send, ask JSON output, progress post, runtime detection, and registered sessions.
// Dependencies: session_identity_support sandbox and synthetic HTTP.

mod session_identity_support;

use serde_json::json;
use session_identity_support::{
    Fixture,
    http::{Http, Request, Response},
    write_private,
};

fn server(request: &Request) -> Response {
    let body = match (request.method.as_str(), request.path.as_str()) {
        ("POST", "/api/messages") => {
            json!({"id":"msg_1", "status":"sent", "created_at":"2026-10-12"})
        }
        ("POST", "/api/progress") => json!({"id":"post_1", "project":"profiles", "agent_id":"a1",
            "body":"done", "created_at":"2026-10-12"}),
        ("POST", path) if path.starts_with("/api/messages/msg_1/poll") => {
            json!({"id":"msg_1", "replies":[{"id":"reply_1", "direction":"boss_to_agent", "body":"answer",
                "metadata":{"source":"api","provenance":{"version":1,"source":"api","signature":{"status":"not_configured"}}}}]})
        }
        _ => json!({"messages":[], "total":0}),
    };
    Response::json(200, body)
}

fn commands() -> Vec<Vec<&'static str>> {
    vec![
        vec!["send", "hello"],
        vec!["ask", "--json", "hello"],
        vec!["progress", "post", "done"],
    ]
}

#[test]
fn send_profiles_warn_once_inside_claude_and_still_deliver() {
    for args in commands() {
        for signal in [("CLAUDECODE", "1"), ("CLAUDE_CODE_ENTRYPOINT", "cli")] {
            let http = Http::start(server);
            let fixture = Fixture::new("profiles", &http.url);
            let profile = fixture.root.join(".claude-m");
            let profile = profile.to_str().expect("path");
            let out = fixture.run(
                &fixture.repo,
                &args,
                &[("CLAUDE_CONFIG_DIR", profile), signal],
            );
            assert_eq!(out.code, 0, "{args:?}: {} {}", out.stdout, out.stderr);
            assert_eq!(
                out.stderr
                    .matches("messages will appear as direct messages")
                    .count(),
                1
            );
            assert!(out.stderr.contains(profile));
            assert!(out.stderr.contains(&format!(
                "hiboss setup hooks --global --config-dir '{profile}'"
            )));
            assert!(!out.stdout.contains("Warning"));
            if args[0] == "ask" {
                let value: serde_json::Value =
                    serde_json::from_str(&out.stdout).expect("clean JSON");
                assert_eq!(value["body"], "answer");
            }
            let requests = http.requests();
            let post = requests
                .iter()
                .find(|request| request.method == "POST")
                .expect("sent");
            assert!(
                post.body["session_id"].is_null(),
                "unscoped delivery continues"
            );
        }
    }
}

#[test]
fn send_profiles_do_not_warn_outside_claude_even_with_config_dir() {
    for args in commands() {
        let http = Http::start(server);
        let fixture = Fixture::new("profiles", &http.url);
        let profile = fixture.root.join(".claude-m");
        let out = fixture.run(
            &fixture.repo,
            &args,
            &[("CLAUDE_CONFIG_DIR", profile.to_str().expect("path"))],
        );
        assert_eq!(out.code, 0, "{} {}", out.stdout, out.stderr);
        assert!(
            !out.stderr
                .contains("messages will appear as direct messages")
        );
    }
}

#[test]
fn send_profiles_do_not_warn_when_session_is_registered() {
    for args in commands() {
        let http = Http::start(server);
        let fixture = Fixture::new("profiles", &http.url);
        let state = fixture.prepare("claude", "s");
        write_private(&state.join("session"), "registered-session");
        let out = fixture.run(
            &fixture.repo,
            &args,
            &[("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "s")],
        );
        assert_eq!(out.code, 0, "{} {}", out.stdout, out.stderr);
        assert!(
            !out.stderr
                .contains("messages will appear as direct messages")
        );
        let requests = http.requests();
        let post = requests
            .iter()
            .find(|request| request.method == "POST")
            .expect("sent");
        assert_eq!(post.body["session_id"], "registered-session");
    }
}

#[test]
fn send_profiles_warning_names_default_profile_without_override() {
    let http = Http::start(server);
    let fixture = Fixture::new("profiles", &http.url);
    let out = fixture.run(&fixture.repo, &["send", "hello"], &[("CLAUDECODE", "1")]);
    assert_eq!(out.code, 0, "{}", out.stderr);
    assert!(
        out.stderr
            .contains(&fixture.root.join(".claude").display().to_string())
    );
    assert_eq!(
        out.stderr
            .matches("messages will appear as direct messages")
            .count(),
        1
    );
}
