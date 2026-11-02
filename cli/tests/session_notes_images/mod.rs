// Note image downloads through the built CLI and authenticated mock transport.
// Covers private cache reuse, JSON paths and incomplete download acknowledgement.
use super::*;

fn image_server(fail: bool) -> Http {
    Http::start(move |r: &Request| {
        if r.path.contains("/notes?") {
            let mut response = notes(2);
            response["notes"][0]["images"] = json!([
                {"index": 0, "content_type": "image/jpeg", "bytes": 3},
                {"index": 1, "content_type": "image/png", "bytes": 4}
            ]);
            return Response::json(200, response);
        }
        if r.path.ends_with("/images/0") {
            return Response::json(200, json!("abc"));
        }
        if r.path.ends_with("/images/1") {
            return Response::json(200, json!(if fail { "bad" } else { "abcd" }));
        }
        Response::json(
            200,
            json!({"read": 1, "messages": [], "sessions": [], "total": 0}),
        )
    })
}

#[test]
fn images_download_privately_reuse_complete_files_and_print_json_paths() {
    let http = image_server(false);
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    let result = fixture.run(&fixture.repo, &["note", "list", "--json"], ENV);
    assert_eq!(result.code, 0, "{}", result.stderr);
    let output: Value = serde_json::from_str(&result.stdout).expect("notes");
    let path = Path::new(
        output["notes"][0]["images"][0]["path"]
            .as_str()
            .expect("image path"),
    );
    assert!(path.ends_with("hiboss/notes/note-0/0.jpg"));
    assert_eq!(std::fs::read(path).expect("image"), b"abc");
    assert_private_cache(path);
    let result = fixture.run(&fixture.repo, &["note", "read"], ENV);
    assert_eq!(result.code, 0, "{}", result.stderr);
    assert!(result.stdout.contains("image 1/2:"));
    assert!(
        result
            .stdout
            .contains("(image/jpeg, 1 KB) — open it to view")
    );
    let result = fixture.run(&fixture.repo, &["hook", "bg-check"], ENV);
    assert_eq!(result.code, 0, "{}", result.stderr);
    prime_ttls(&fixture.state_dir("claude", "notes"));
    let result = fixture.run(&fixture.repo, &["hook", "post-tool-use"], ENV);
    assert!(result.stdout.contains("left 2 note(s) with 2 image(s)"));
    let requests = http.requests();
    assert_eq!(
        requests
            .iter()
            .filter(|r| r.path.contains("/images/"))
            .count(),
        2
    );
    assert!(
        requests
            .iter()
            .filter(|r| r.path.contains("/images/"))
            .all(|r| r.header("authorization") == Some("Bearer synthetic-claude-key"))
    );
    assert!(
        requests
            .iter()
            .any(|r| r.body["ids"] == json!(["note-0", "note-1"]))
    );
}

fn assert_private_cache(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    assert_eq!(
        std::fs::metadata(path).expect("file").permissions().mode() & 0o777,
        0o600
    );
    for dir in path.ancestors().skip(1).take(3) {
        assert_eq!(
            std::fs::metadata(dir)
                .expect("directory")
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
    }
}

#[test]
fn incomplete_images_report_errors_and_only_complete_notes_are_acknowledged() {
    let http = image_server(true);
    let fixture = Fixture::new("repo", &http.url);
    prepare(&fixture);
    let result = fixture.run(&fixture.repo, &["note", "read", "--json"], ENV);
    assert_eq!(result.code, 0, "{}", result.stderr);
    assert!(
        result
            .stderr
            .contains("Note note-0 image 1: incomplete image download")
    );
    let output: Value = serde_json::from_str(&result.stdout).expect("notes");
    assert!(output["notes"][0]["images"][1]["path"].is_null());
    let path = Path::new(
        output["notes"][0]["images"][0]["path"]
            .as_str()
            .expect("path"),
    );
    assert_eq!(
        std::fs::read_dir(path.parent().expect("cache"))
            .expect("files")
            .count(),
        1
    );
    let requests = http.requests();
    let marks: Vec<_> = requests
        .iter()
        .filter(|r| r.path.ends_with("/notes/read"))
        .collect();
    assert_eq!(marks.len(), 1);
    assert_eq!(marks[0].body["ids"], json!(["note-1"]));
}
