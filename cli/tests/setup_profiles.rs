// Exercises Claude profile discovery through the built CLI with an isolated HOME.
// Covers global installation, refresh, removal, and preservation of unmanaged bytes.
// Dependencies: session_identity_support sandbox, serde_json, filesystem.

mod session_identity_support;

use session_identity_support::Fixture;
use std::fs;
use std::os::unix::fs::symlink;

fn profiles() -> Fixture {
    let fixture = Fixture::new("profiles", "http://127.0.0.1:1");
    for name in [".claude", ".claude-m", ".claude-foo"] {
        fs::create_dir_all(fixture.root.join(name)).expect("profile directory");
    }
    fs::create_dir_all(fixture.root.join(".claude-m/projects")).expect("projects");
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
    fs::create_dir_all(fixture.root.join(".claude-settings-only")).expect("settings-only");
    fs::write(
        fixture.root.join(".claude-settings-only/settings.json"),
        "{\"settings_only\":true}",
    )
    .expect("settings-only file");
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
    assert_eq!(
        fs::read_to_string(fixture.root.join(".claude-settings-only/settings.json"))
            .expect("settings-only file"),
        "{\"settings_only\":true}"
    );
}

#[test]
fn setup_preserves_symlinked_settings_and_instructions_targets() {
    let fixture = profiles();
    let outside = fixture.root.join("outside");
    fs::create_dir_all(&outside).expect("outside directory");
    let target = outside.join("settings.json");
    fs::write(&target, "{\"owned\":true}").expect("target settings");
    let instructions_target = outside.join("CLAUDE.md");
    fs::write(&instructions_target, "user instructions\n").expect("target instructions");
    let profile = fixture.root.join(".claude");
    symlink(&target, profile.join("settings.json")).expect("settings symlink");
    symlink(&instructions_target, profile.join("CLAUDE.md")).expect("instructions symlink");

    let out = fixture.run(
        &fixture.repo,
        &[
            "setup",
            "hooks",
            "--config-dir",
            profile.to_str().expect("profile"),
        ],
        &[],
    );

    assert_eq!(out.code, 0, "{}", out.stderr);
    assert!(fs::symlink_metadata(profile.join("settings.json"))
        .expect("settings metadata")
        .file_type()
        .is_symlink());
    assert!(fs::symlink_metadata(profile.join("CLAUDE.md"))
        .expect("instructions metadata")
        .file_type()
        .is_symlink());
    let settings: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(target).expect("target settings"))
            .expect("target settings JSON");
    assert!(settings["hooks"]["SessionStart"].is_array());
    assert!(fs::read_to_string(instructions_target)
        .expect("target instructions")
        .contains("hiboss"));
}

#[test]
fn setup_skips_symlinked_discovered_profiles_and_reports_them() {
    let fixture = profiles();
    let outside = fixture.root.join("outside-profile");
    fs::create_dir_all(outside.join("projects")).expect("outside projects");
    symlink(&outside, fixture.root.join(".claude-linked")).expect("profile symlink");

    let out = fixture.run(&fixture.repo, &["setup", "hooks", "--global"], &[]);

    assert_eq!(out.code, 0, "{}", out.stderr);
    assert!(out.stdout.contains(".claude-linked"));
    assert!(out.stdout.contains("skipped"));
    assert!(!outside.join("settings.json").exists());
    assert!(!outside.join("CLAUDE.md").exists());
}

#[test]
fn remove_preserves_commands_that_only_contain_hiboss_hook_text() {
    let fixture = profiles();
    let profile = fixture.root.join(".claude-m");
    let settings = serde_json::json!({
        "hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": "echo \\\"hiboss hook stop\\\""},
            {"type": "command", "command": "hiboss hook stop"},
            {"type": "command", "command": "HIBOSS_PROFILE=claude hiboss hook stop"}
        ]}]}
    });
    fs::write(profile.join("settings.json"), settings.to_string()).expect("settings");

    let out = fixture.run(
        &fixture.repo,
        &[
            "setup",
            "hooks",
            "--config-dir",
            profile.to_str().expect("profile"),
            "--remove",
        ],
        &[],
    );

    assert_eq!(out.code, 0, "{}", out.stderr);
    let updated: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(profile.join("settings.json")).expect("updated"))
            .expect("updated JSON");
    let hooks = updated["hooks"]["Stop"][0]["hooks"]
        .as_array()
        .expect("hooks");
    assert_eq!(hooks.len(), 1);
    assert_eq!(hooks[0]["command"], "echo \\\"hiboss hook stop\\\"");
}
