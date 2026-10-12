// Exercises Claude profile discovery through the built CLI with an isolated HOME.
// Covers global installation, refresh, removal, and preservation of unmanaged bytes.
// Dependencies: session_identity_support sandbox, serde_json, filesystem.

mod session_identity_support;

use session_identity_support::Fixture;
use std::fs;

fn profiles() -> Fixture {
    let fixture = Fixture::new("profiles", "http://127.0.0.1:1");
    for name in [".claude", ".claude-m", ".claude-foo"] {
        fs::create_dir_all(fixture.root.join(name)).expect("profile directory");
    }
    fs::create_dir_all(fixture.root.join(".claude-second/projects")).expect("projects");
    fs::write(fixture.root.join(".claude-m/settings.json"), "{}").expect("settings");
    fs::write(
        fixture.root.join(".claude-m/settings.json.bak-123"),
        "backup bytes",
    )
    .expect("backup");
    fs::write(
        fixture.root.join(".claude-foo/settings.json.bak-123"),
        "backup only",
    )
    .expect("backup-only directory");
    fixture
}

#[test]
fn setup_global_includes_environment_profile_and_removes_all_discovered_hooks() {
    let fixture = profiles();
    let extra = fixture.root.join("custom Claude");
    let extra = extra.to_str().expect("path");
    let env = [("CLAUDE_CONFIG_DIR", extra)];
    let out = fixture.run(&fixture.repo, &["setup", "hooks", "--global"], &env);
    assert_eq!(out.code, 0, "{}", out.stderr);
    assert_eq!(out.stdout.lines().count(), 4, "one result per profile");
    let out = fixture.run(
        &fixture.repo,
        &["setup", "hooks", "--global", "--remove"],
        &env,
    );
    assert_eq!(out.code, 0, "{}", out.stderr);
    assert_eq!(out.stdout.lines().count(), 4);
    for name in [".claude", ".claude-m", ".claude-second", "custom Claude"] {
        let raw =
            fs::read_to_string(fixture.root.join(name).join("settings.json")).expect("settings");
        assert!(!raw.contains("hiboss hook"));
    }
    assert!(!fixture.root.join(".claude-foo/settings.json").exists());
}

#[test]
fn setup_config_dir_targets_one_profile_and_is_idempotent() {
    let fixture = profiles();
    let target = fixture.root.join(".claude-m");
    let target = target.to_str().expect("path");
    let args = ["setup", "hooks", "--config-dir", target];
    let first = fixture.run(&fixture.repo, &args, &[]);
    assert_eq!(first.code, 0, "{}", first.stderr);
    assert_eq!(first.stdout.lines().count(), 1);
    assert!(!fixture.root.join(".claude/settings.json").exists());
    assert!(!fixture.root.join(".claude-second/settings.json").exists());
    let path = fixture.root.join(".claude-m/settings.json");
    let raw = fs::read_to_string(&path).expect("installed");
    let second = fixture.run(&fixture.repo, &args, &[]);
    assert_eq!(second.code, 0, "{}", second.stderr);
    assert_eq!(fs::read_to_string(&path).expect("unchanged"), raw);
    let out = fixture.run(
        &fixture.repo,
        &["setup", "hooks", "--config-dir", target, "--remove"],
        &[],
    );
    assert_eq!(out.code, 0, "{}", out.stderr);
    assert_eq!(fs::read_to_string(&path).expect("removed"), "{}");
}

#[test]
fn setup_global_continues_past_malformed_profile_and_reports_failure() {
    let fixture = profiles();
    let broken = fixture.root.join(".claude-m/settings.json");
    fs::write(&broken, "{broken").expect("broken settings");
    let out = fixture.run(&fixture.repo, &["setup", "hooks", "--global"], &[]);
    assert_ne!(out.code, 0);
    assert!(out.stderr.contains("hook setup failed"));
    assert!(fixture.root.join(".claude/settings.json").is_file());
    assert!(fixture.root.join(".claude-second/settings.json").is_file());
    assert_eq!(fs::read_to_string(broken).expect("preserved"), "{broken");
}

#[test]
fn setup_global_deduplicates_environment_profile() {
    let fixture = profiles();
    let target = fixture.root.join(".claude-m");
    let out = fixture.run(
        &fixture.repo,
        &["setup", "hooks", "--global"],
        &[("CLAUDE_CONFIG_DIR", target.to_str().expect("path"))],
    );
    assert_eq!(out.code, 0, "{}", out.stderr);
    assert_eq!(out.stdout.lines().count(), 3);
}

#[test]
fn setup_profile_preserves_settings_bytes_and_other_tools_hooks() {
    let fixture = profiles();
    let target = fixture.root.join(".claude-m");
    let path = target.join("settings.json");
    let other =
        r#"{ "matcher" : "", "hooks" : [{"type" : "command", "command" : "other-tool run"}] }"#;
    let raw = format!(
        "{{\n  \"theme\" : \"\\u0064ark\", \"number\" : 1e2,\n  \"hooks\" : {{\"Stop\":[{other}]}}\n}}\n"
    );
    fs::write(&path, &raw).expect("settings");
    let target = target.to_str().expect("path");
    let install = fixture.run(
        &fixture.repo,
        &["setup", "hooks", "--config-dir", target],
        &[],
    );
    assert_eq!(install.code, 0, "{}", install.stderr);
    let installed = fs::read_to_string(&path).expect("installed");
    assert!(installed.contains(other));
    assert!(installed.contains(r#""theme" : "\u0064ark", "number" : 1e2"#));
    let remove = fixture.run(
        &fixture.repo,
        &["setup", "hooks", "--config-dir", target, "--remove"],
        &[],
    );
    assert_eq!(remove.code, 0, "{}", remove.stderr);
    assert_eq!(fs::read_to_string(&path).expect("removed"), raw);
}

#[test]
fn setup_global_installs_every_profile_without_config_override() {
    let fixture = profiles();
    let out = fixture.run(&fixture.repo, &["setup", "hooks", "--global"], &[]);
    assert_eq!(out.code, 0, "{}", out.stderr);
    for name in [".claude", ".claude-m", ".claude-second"] {
        let path = fixture.root.join(name);
        let raw = fs::read_to_string(path.join("settings.json")).expect("profile installed");
        let value: serde_json::Value = serde_json::from_str(&raw).expect("settings JSON");
        assert_eq!(
            value["hooks"]["SessionStart"][0]["hooks"][0]["command"],
            "HIBOSS_PROFILE=claude hiboss hook session-start"
        );
        assert!(
            out.stdout.contains(&path.display().to_string()),
            "{}",
            out.stdout
        );
    }
    assert!(!fixture.root.join(".claude-foo/settings.json").exists());
    assert_eq!(
        fs::read_to_string(fixture.root.join(".claude-m/settings.json.bak-123")).expect("backup"),
        "backup bytes"
    );
}
