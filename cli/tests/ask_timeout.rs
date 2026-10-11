// Exercises ask's send payload, repeated poll windows, retries, and deadline via the binary.
// Uses synthetic loopback HTTP and isolated CLI config; no operator credentials.
// Dependencies: existing HTTP and Sandbox fixtures, serde_json, and std clocks.

#[path = "onboarding_support/http.rs"]
mod http;
#[path = "cli_ux_support/mod.rs"]
mod sandbox;

use http::{Http, Request, Response};
use sandbox::{Outcome, Sandbox};
use serde_json::{Value, json};
use std::sync::atomic::{AtomicUsize, Ordering};

fn serve(request: &Request, poll: impl FnOnce() -> Response) -> Response {
    if request.path.contains("/poll?") {
        return poll();
    }
    match (request.method.as_str(), request.path.as_str()) {
        ("POST", "/api/messages") => Response::json(
            201,
            json!({"id":"ask-1", "status":"sent", "created_at":"2026-10-11T17:25:00Z"}),
        ),
        ("PATCH", "/api/messages/reply-1") => Response::json(200, json!({"id":"reply-1"})),
        _ => Response::json(404, json!("unexpected endpoint")),
    }
}

fn poll_response(reply: Option<Value>) -> Response {
    Response::json(
        200,
        json!({"id":"ask-1", "replies":reply.into_iter().collect::<Vec<_>>()}),
    )
}

fn ask(http: &Http, timeout: &str, default: bool) -> Outcome {
    let sandbox = Sandbox::new();
    sandbox.write_config(
        &json!({
            "version":2, "server":http.url, "default_profile":"claude", "channel":null,
            "profiles":{"claude":{
                "key":"synthetic-ask-key", "agent_id":"a1", "name":"ask-test", "server":null,
            }},
        })
        .to_string(),
    );
    let mut args = vec![
        "ask",
        "Choose",
        "--option",
        "A",
        "--option",
        "B",
        "--timeout",
        timeout,
        "--json",
    ];
    if default {
        args.extend(["--default", "A"]);
    }
    sandbox.run_loopback(&args)
}

fn result(output: &Outcome) -> Value {
    assert_eq!(output.code, 0, "{}", output.stderr);
    serde_json::from_str(&output.stdout).expect("ask JSON result")
}

#[test]
fn later_poll_returns_boss_reply_and_sends_chosen_timeout() {
    let polls = AtomicUsize::new(0);
    let http = Http::start(move |request| {
        serve(request, || match polls.fetch_add(1, Ordering::SeqCst) {
            0 => poll_response(None),
            _ => poll_response(Some(json!({"id":"reply-1", "body":"B"}))),
        })
    });
    let output = ask(&http, "86400", false);
    let result = result(&output);
    assert_eq!(result["outcome"], "reply");
    assert_eq!(result["body"], "B");
    let requests = http.requests();
    let sent = requests
        .iter()
        .find(|r| r.path == "/api/messages")
        .expect("send");
    assert_eq!(sent.body["timeout"], 86400);
    assert_eq!(sent.body["mode"], "blocking");
    let polls: Vec<_> = requests
        .iter()
        .filter(|r| r.path.contains("/poll?"))
        .collect();
    assert_eq!(polls.len(), 2);
    assert!(polls.iter().all(|r| r.path.ends_with("timeout=300")));
}

#[test]
fn transient_poll_error_retries_and_preserves_auto_default_provenance() {
    let polls = AtomicUsize::new(0);
    let http = Http::start(move |request| {
        serve(request, || match polls.fetch_add(1, Ordering::SeqCst) {
            0 => Response::json(503, json!("temporarily unavailable")),
            _ => poll_response(Some(json!({
                "id":"reply-1", "body":"A", "metadata":{"auto_default":true},
            }))),
        })
    });
    let output = ask(&http, "60", true);
    assert_eq!(result(&output)["outcome"], "auto_default");
    assert!(output.stderr.contains("retrying"));
    let polls = http
        .requests()
        .iter()
        .filter(|r| r.path.contains("/poll?"))
        .count();
    assert_eq!(polls, 2);
}

#[test]
fn permanent_poll_error_aborts_without_retry() {
    let http = Http::start(|request| serve(request, || Response::json(401, json!("Unauthorized"))));
    let output = ask(&http, "60", false);
    assert_ne!(output.code, 0);
    assert!(output.stderr.contains("401"));
    assert_eq!(
        http.requests()
            .iter()
            .filter(|r| r.path.contains("/poll?"))
            .count(),
        1
    );
}
