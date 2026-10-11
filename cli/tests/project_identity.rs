// Drives project set and set-avatar against a mock server to verify local identity isolation.
// Covers canonical slugs, aliases, avatar-only foreign updates, and local sync bookkeeping.
// Dependencies: session_identity_support (isolated CLI + HTTP fixtures), serde_json, std::fs.

mod session_identity_support;
use serde_json::{Value, json};
use session_identity_support::http::{Http, Request, Response};
use session_identity_support::{Fixture, fnv};
use std::fs;

const FILES: [&str; 4] = ["team.json", "avatar.png", "state.json", ".gitignore"];
const AVATAR: &str = "new avatar bytes";

fn canonical(project: &str) -> &str {
    match project {
        "repo-alias" | "hiboss-alias" => "hiboss",
        "ai-dispatch-alias" => "ai-dispatch",
        project => project,
    }
}

fn server() -> Http {
    Http::start(|request: &Request| {
        if request.path == "/api/attachments/upload" {
            return Response::json(
                200,
                json!({
                    "key": "avatar", "url": "https://example.test/avatar.png",
                    "filename": "new.png", "content_type": "image/png", "size": AVATAR.len()
                }),
            );
        }
        let project = canonical(request.path.rsplit('/').next().expect("project path"));
        Response::json(
            200,
            json!({
                "project": project, "handle": project, "display_name": "Server profile",
                "bio": "Server bio", "avatar_url": "https://example.test/avatar.png"
            }),
        )
    })
}

fn fixture(http: &Http, origin: &str, local: bool) -> Fixture {
    let fixture = Fixture::new("checkout", &http.url);
    fixture.git(&fixture.repo, &["remote", "add", "origin", origin]);
    fs::write(fixture.repo.join("new.png"), AVATAR).expect("input avatar");
    if local {
        let dir = fixture.repo.join(".hiboss");
        fs::create_dir(&dir).expect("local directory");
        for (name, content) in FILES.into_iter().zip([
            "{\"handle\":\"local\",\"display_name\":\"Local profile\",\"bio\":\"Local bio\"}\n",
            "old avatar bytes",
            "{\"synced_hash\":\"unsynced\"}\n",
            "state.json\ncustom\n",
        ]) {
            fs::write(dir.join(name), content).expect("local file");
        }
    }
    fixture
}

fn snapshot(fixture: &Fixture) -> Vec<Vec<u8>> {
    FILES
        .iter()
        .map(|name| fs::read(fixture.repo.join(".hiboss").join(name)).expect("local file bytes"))
        .collect()
}

fn run(fixture: &Fixture, command: &str, project: &str) -> String {
    let args = if command == "set" {
        vec![
            "project",
            "set",
            "--project",
            project,
            "--avatar",
            "new.png",
            "--display-name",
            "Requested profile",
        ]
    } else {
        vec!["project", "set-avatar", "new.png", "--project", project]
    };
    let output = fixture.run(&fixture.repo, &args, &[]);
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert!(
        output
            .stdout
            .contains(&format!("project: {}", canonical(project)))
    );
    output.stderr
}

fn assert_foreign_update(requests: &[Request], command: &str, project: &str) {
    let updates: Vec<_> = requests.iter().filter(|r| r.method == "PUT").collect();
    assert_eq!(updates.len(), 1, "exactly one target update");
    assert_eq!(updates[0].path, format!("/api/progress/teams/{project}"));
    assert_eq!(requests.iter().filter(|r| r.method == "POST").count(), 1);
    let mut expected = json!({"avatar_url": "https://example.test/avatar.png"});
    if command == "set" {
        expected["display_name"] = json!("Requested profile");
    }
    assert_eq!(updates[0].body, expected, "no local profile fields sent");
}

fn foreign_project(command: &str, project: &str) {
    let http = server();
    let fixture = fixture(&http, "git@example.test:org/hiboss.git", true);
    let before = snapshot(&fixture);
    let stderr = run(&fixture, command, project);
    assert_eq!(
        snapshot(&fixture),
        before,
        "all local files must remain byte-identical"
    );
    assert!(stderr.contains(
        "local .hiboss not changed: target project ai-dispatch differs from this repository's hiboss"
    ), "{stderr}");
    assert_foreign_update(&http.requests(), command, project);
}

fn current_project(command: &str, project: &str, origin: &str) {
    let http = server();
    let fixture = fixture(&http, origin, true);
    let stderr = run(&fixture, command, project);
    assert!(!stderr.contains("local .hiboss not changed"), "{stderr}");
    let dir = fixture.repo.join(".hiboss");
    let content = fs::read_to_string(dir.join("team.json")).expect("updated profile");
    let team: Value = serde_json::from_str(&content).expect("profile JSON");
    assert_eq!(team["avatar"], "avatar.png");
    let (handle, name, bio) = if command == "set" {
        ("hiboss", "Server profile", "Server bio")
    } else {
        ("local", "Local profile", "Local bio")
    };
    assert_eq!(team["handle"], handle);
    assert_eq!(team["display_name"], name);
    assert_eq!(team["bio"], bio);
    assert_eq!(
        fs::read_to_string(dir.join("avatar.png")).expect("avatar"),
        AVATAR
    );
    let state: Value = serde_json::from_slice(&fs::read(dir.join("state.json")).expect("state"))
        .expect("state JSON");
    assert_eq!(state["synced_hash"], fnv(&content));
    assert_eq!(
        fs::read_to_string(dir.join(".gitignore")).expect("ignore"),
        "state.json\ncustom\n"
    );
    let requests = http.requests();
    let update = requests
        .iter()
        .find(|r| r.method == "PUT")
        .expect("profile update");
    assert_eq!(update.path, format!("/api/progress/teams/{project}"));
    if command == "set-avatar" {
        assert_eq!(
            update.body,
            json!({
                "handle": "local", "display_name": "Local profile", "bio": "Local bio",
                "avatar_url": "https://example.test/avatar.png"
            })
        );
    }
}

#[test]
fn set_other_project_preserves_local_identity() {
    foreign_project("set", "ai-dispatch");
}

#[test]
fn set_avatar_other_project_preserves_local_identity_and_sends_only_avatar() {
    foreign_project("set-avatar", "ai-dispatch");
}

#[test]
fn set_current_project_writes_local_identity() {
    current_project("set", "hiboss", "git@example.test:org/hiboss.git");
}

#[test]
fn set_avatar_current_project_writes_local_avatar_and_state() {
    current_project("set-avatar", "hiboss", "git@example.test:org/hiboss.git");
}

#[test]
fn other_project_aliases_preserve_local_identity_for_both_commands() {
    for command in ["set", "set-avatar"] {
        foreign_project(command, "ai-dispatch-alias");
    }
}

#[test]
fn current_project_aliases_write_local_identity_for_both_commands() {
    for command in ["set", "set-avatar"] {
        current_project(command, "hiboss-alias", "git@example.test:org/hiboss.git");
    }
}

#[test]
fn repository_alias_is_resolved_before_comparing_both_commands() {
    for command in ["set", "set-avatar"] {
        current_project(command, "hiboss", "git@example.test:org/Repo-Alias.git");
    }
}

#[test]
fn foreign_updates_do_not_create_local_directory_for_both_commands() {
    for command in ["set", "set-avatar"] {
        let http = server();
        let fixture = fixture(&http, "git@example.test:org/hiboss.git", false);
        run(&fixture, command, "ai-dispatch");
        assert!(!fixture.repo.join(".hiboss").exists());
        assert_foreign_update(&http.requests(), command, "ai-dispatch");
    }
}

#[test]
fn foreign_set_avatar_succeeds_with_unreadable_local_profile() {
    let http = server();
    let fixture = fixture(&http, "git@example.test:org/hiboss.git", true);
    fs::write(fixture.repo.join(".hiboss/team.json"), "invalid JSON").expect("broken profile");
    let before = snapshot(&fixture);
    run(&fixture, "set-avatar", "ai-dispatch");
    assert_eq!(snapshot(&fixture), before);
    assert_foreign_update(&http.requests(), "set-avatar", "ai-dispatch");
}

#[test]
fn unresolved_repository_preserves_local_identity_for_both_commands() {
    for command in ["set", "set-avatar"] {
        let http = Http::start(|request: &Request| {
            if request.path == "/api/progress/teams/hiboss" {
                return Response::json(404, json!("project not found"));
            }
            if request.method == "POST" {
                return Response::json(
                    200,
                    json!({
                        "key": "avatar", "url": "https://example.test/avatar.png",
                        "filename": "new.png", "content_type": "image/png", "size": AVATAR.len()
                    }),
                );
            }
            Response::json(
                200,
                json!({
                    "project": "ai-dispatch", "handle": "ai-dispatch", "display_name": "Other",
                    "bio": null, "avatar_url": "https://example.test/avatar.png"
                }),
            )
        });
        let fixture = fixture(&http, "git@example.test:org/hiboss.git", true);
        let before = snapshot(&fixture);
        let stderr = run(&fixture, command, "ai-dispatch");
        assert!(
            stderr.contains("cannot resolve this repository's project hiboss"),
            "{stderr}"
        );
        assert_eq!(snapshot(&fixture), before);
        assert_foreign_update(&http.requests(), command, "ai-dispatch");
    }
}
