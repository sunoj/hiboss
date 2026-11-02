// CLI reply contract exercised through the real binary and mock HTTP transport.
// Shares session fixtures with session_notes; validates send payloads and rendered history.
use super::*;

#[test]
fn note_reply_uses_current_session_and_prints_message_receipt() {
    let http = Http::start(|r: &Request| {
        assert_eq!(r.path, "/api/messages");
        assert_eq!(r.method, "POST");
        assert_eq!(r.body["body"], "Done");
        assert_eq!(r.body["session_id"], "sid");
        assert_eq!(r.body["metadata"]["note_id"], "note-0");
        assert_eq!(r.body["mode"], "async");
        assert!(r.body["to"].is_null());
        assert!(r.body["options"].is_null());
        Response::json(
            201,
            json!({"id": "reply-message", "status": "sent", "created_at": "now"}),
        )
    });
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    let result = fixture.run(&fixture.repo, &["note", "reply", "note-0", "Done"], ENV);
    assert_eq!(result.code, 0, "{}", result.stderr);
    assert_eq!(result.stdout.trim(), "reply-message");
    assert_eq!(http.requests().len(), 1);
}

#[test]
fn note_reply_content_file_preserves_long_text_and_propagates_errors() {
    let http = Http::start(|r: &Request| {
        assert_eq!(
            r.body["metadata"]["content"],
            "Full\nreply details".repeat(40)
        );
        Response::json(
            400,
            json!({"error": "note does not belong to this session and agent"}),
        )
    });
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    let file = fixture.repo.join("reply.md");
    std::fs::write(&file, "Full\nreply details".repeat(40)).expect("content file");
    let result = fixture.run(
        &fixture.repo,
        &[
            "note",
            "reply",
            "note-0",
            "Details",
            "--content-file",
            file.to_str().expect("path"),
        ],
        ENV,
    );
    assert_ne!(result.code, 0);
    assert!(result.stderr.contains("note does not belong"));
    assert!(!result.stdout.contains("reply-message"));
    assert_eq!(http.requests().len(), 1);
}

#[test]
fn note_read_and_list_render_replies_and_include_them_in_json() {
    let http = Http::start(|r: &Request| {
        if r.path.ends_with("/notes/read") {
            return Response::json(200, json!({"read": 1}));
        }
        let mut response = notes(1);
        response["notes"][0]["replies"] = json!([{
            "message_id": "reply-1", "body": "Full\nreply", "agent_name": "Agent",
            "created_at": "2026-11-02 11:00:00"
        }]);
        Response::json(200, response)
    });
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    for command in ["read", "list"] {
        let result = fixture.run(&fixture.repo, &["note", command], ENV);
        assert_eq!(result.code, 0, "{}", result.stderr);
        assert!(
            result
                .stdout
                .contains("Agent · 2026-11-02 11:00:00 · reply-1\nFull\nreply")
        );
        assert!(
            result
                .stdout
                .trim_end()
                .ends_with("Reply: hiboss note reply note-0 \"<text>\"")
        );
        let result = fixture.run(&fixture.repo, &["note", command, "--json"], ENV);
        assert_eq!(result.code, 0, "{}", result.stderr);
        let response: Value = serde_json::from_str(&result.stdout).expect("JSON");
        assert_eq!(response["notes"][0]["replies"][0]["body"], "Full\nreply");
    }
}
