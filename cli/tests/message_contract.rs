// Exercises title validation and Markdown content delivery through the real CLI.
// Uses an isolated configuration and mock HTTP server; no operator credentials.

mod session_identity_support;
use serde_json::json;
use session_identity_support::{
    Fixture,
    http::{Http, Response},
};

#[test]
fn rejects_overlong_titles_before_any_http_request() {
    let http = Http::start(|_| {
        Response::json(
            201,
            json!({"id":"m", "status":"sent", "created_at":"2026-10-11T00:00:00Z"}),
        )
    });
    let fixture = Fixture::new("house", &http.url);
    let long = "字".repeat(145);
    for args in [vec!["send", long.as_str()], vec!["ask", long.as_str()]] {
        let run = fixture.run(&fixture.repo, &args, &[]);
        assert_ne!(run.code, 0);
        assert!(run.stderr.contains("144"), "{}", run.stderr);
    }
    assert!(
        http.requests().is_empty(),
        "invalid titles must not notify or upload"
    );
}

#[test]
fn sends_a_unicode_title_with_the_complete_markdown_file_as_content() {
    let http = Http::start(|request| match request.path.as_str() {
        "/api/messages" => Response::json(
            201,
            json!({"id":"m", "status":"sent", "created_at":"2026-10-11T00:00:00Z"}),
        ),
        _ => Response::json(200, json!({"messages":[], "total":0})),
    });
    let fixture = Fixture::new("house", &http.url);
    let markdown =
        "# Result\n\n**Ready**\n\n- First item\n- Second item\n\n```swift\nlet ready = true\n```";
    let file = fixture.root.join("report.md");
    std::fs::write(&file, markdown).expect("report");
    let title = "🏠".repeat(144);
    let run = fixture.run(
        &fixture.repo,
        &[
            "send",
            &title,
            "--content-file",
            file.to_str().expect("path"),
        ],
        &[],
    );
    assert_eq!(run.code, 0, "{}", run.stderr);
    let requests = http.requests();
    let sent = requests.iter().find(|r| r.method == "POST").expect("sent");
    assert_eq!(sent.body["body"], title);
    assert_eq!(sent.body["metadata"]["content"], markdown);
}
