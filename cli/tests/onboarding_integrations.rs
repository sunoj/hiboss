// Verifies built-binary runtime integrations and profile-authenticated invite minting.
// Covers configured destinations, managed guidance preservation, and refreshed Claude hooks.
// Dependencies: filesystem sandboxes and synthetic std HTTP fixtures.

mod onboarding_support;
use onboarding_support::http::{Http, Response};
use onboarding_support::*;
use serde_json::{Value, json};
use std::fs;

const GUIDANCE: &str = "# Existing guidance\nKeep changes concise.\n\n<!-- hiboss:panels:begin -->\nOld managed text.\n<!-- hiboss:panels:end -->\n\nKeep this trailing note.\n";

#[test]
fn invite_mint_uses_the_selected_profile_key_and_prints_a_self_contained_prompt() {
    let sandbox = Sandbox::new();
    let server = Http::start(|_| {
        Response::json(
            201,
            json!({"invite":INVITE, "expires_at":"2099-01-01T00:00:00Z", "inviter_label":"synthetic-machine"}),
        )
    });
    existing_config(&sandbox, &server.url);
    let mut config = saved_config(&sandbox);
    config["profiles"]["codex"] = json!({"key":"synthetic-inviter-codex-key", "agent_id":"synthetic-codex", "name":"codex@host"});
    sandbox.write_config(&config.to_string());
    let before = sandbox.read_config();
    let output = sandbox.run_input(
        &["device", "invite"],
        "",
        &[("NO_PROXY", "127.0.0.1"), ("HIBOSS_PROFILE", "codex")],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    assert!(output.stdout.contains(&server.url) && output.stdout.contains(INVITE));
    assert!(output.stdout.contains("hiboss setup --server") && output.stdout.contains("--invite"));
    assert!(
        output
            .stdout
            .contains("cargo install --git https://github.com/sunoj/hiboss hiboss")
    );
    assert!(
        output.stdout.contains("6-digit verification code") && output.stdout.contains("works once")
    );
    assert_no_secrets(&output, &[EXISTING_KEY, "synthetic-inviter-codex-key"]);
    assert_eq!(sandbox.read_config(), before);
    let requests = server.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(
        (&*requests[0].method, &*requests[0].path),
        ("POST", "/api/devices/invites")
    );
    assert_eq!(
        requests[0].header("authorization"),
        Some("Bearer synthetic-inviter-codex-key")
    );
}

#[test]
fn grouped_setup_installs_guidance_in_runtime_config_directories() {
    let sandbox = Sandbox::new();
    let server = join_server("approved");
    let claude = sandbox.home.join("custom-claude");
    let codex = sandbox.home.join("custom-codex");
    let gemini = sandbox.home.join(".gemini");
    for (directory, name) in [
        (&claude, "CLAUDE.md"),
        (&codex, "AGENTS.md"),
        (&gemini, "GEMINI.md"),
    ] {
        fs::create_dir_all(directory).expect("runtime directory");
        fs::write(directory.join(name), GUIDANCE).expect("initial guidance");
    }
    fs::write(claude.join("settings.json"), legacy_hooks().to_string()).expect("legacy hooks");
    let args = profile_arguments(&server.url, &["claude", "codex", "gemini"]);
    let output = sandbox.run_input(
        &args,
        "",
        &[
            ("NO_PROXY", "127.0.0.1"),
            ("CLAUDE_CONFIG_DIR", claude.to_str().expect("path")),
            ("CODEX_HOME", codex.to_str().expect("path")),
        ],
    );
    assert_eq!(output.code, 0, "{}", output.stderr);
    for (directory, name) in [
        (&claude, "CLAUDE.md"),
        (&codex, "AGENTS.md"),
        (&gemini, "GEMINI.md"),
    ] {
        let guidance = fs::read_to_string(directory.join(name)).expect("installed guidance");
        assert!(guidance.starts_with("# Existing guidance\nKeep changes concise."));
        assert!(guidance.ends_with("Keep this trailing note.\n"));
        assert_eq!(guidance.matches("<!-- hiboss:panels:begin -->").count(), 1);
        assert!(!guidance.contains("Old managed text."));
    }
    assert_profile_hooks(
        &serde_json::from_str(&fs::read_to_string(claude.join("settings.json")).expect("settings"))
            .expect("JSON"),
    );
    assert!(!sandbox.home.join(".claude/settings.json").exists());
    assert!(!sandbox.home.join(".codex/AGENTS.md").exists());
    assert_private_config(&sandbox);
}

#[test]
fn global_hook_refresh_and_removal_preserve_unrelated_settings_and_guidance() {
    let sandbox = Sandbox::new();
    let directory = sandbox.home.join("claude-override");
    fs::create_dir_all(&directory).expect("Claude directory");
    fs::write(directory.join("settings.json"), legacy_hooks().to_string()).expect("legacy hooks");
    fs::write(directory.join("CLAUDE.md"), GUIDANCE).expect("guidance");
    let extra = [("CLAUDE_CONFIG_DIR", directory.to_str().expect("path"))];
    for _ in 0..2 {
        let output = sandbox.run_input(&["setup", "hooks", "--global"], "", &extra);
        assert_eq!(output.code, 0, "{}", output.stderr);
        let settings: Value = serde_json::from_str(
            &fs::read_to_string(directory.join("settings.json")).expect("settings"),
        )
        .expect("JSON");
        assert_profile_hooks(&settings);
    }
    let output = sandbox.run_input(&["setup", "hooks", "--global", "--remove"], "", &extra);
    assert_eq!(output.code, 0, "{}", output.stderr);
    let settings: Value = serde_json::from_str(
        &fs::read_to_string(directory.join("settings.json")).expect("settings"),
    )
    .expect("JSON");
    assert_eq!(settings["theme"], "dark");
    assert_eq!(
        settings["hooks"]["SessionStart"][0]["hooks"],
        json!([{"type":"command", "command":"other-tool check"}])
    );
    let guidance = fs::read_to_string(directory.join("CLAUDE.md")).expect("guidance");
    assert!(
        guidance.contains("Keep changes concise.") && guidance.contains("Keep this trailing note.")
    );
    assert!(!guidance.contains("<!-- hiboss:panels:begin -->"));
}

fn legacy_hooks() -> Value {
    json!({"theme":"dark", "hooks": {"SessionStart": [{"matcher":"", "hooks":[
        {"type":"command", "command":"other-tool check"},
        {"type":"command", "command":"HIBOSS_PROFILE=old hiboss hook session-start", "timeout":12}
    ]}]}})
}

fn assert_profile_hooks(settings: &Value) {
    assert_eq!(settings["theme"], "dark");
    assert_eq!(
        settings["hooks"]["SessionStart"][0]["hooks"][0]["command"],
        "other-tool check"
    );
    assert_eq!(
        settings["hooks"]["SessionStart"][0]["hooks"][1]["timeout"],
        12
    );
    for (event, label) in [
        ("SessionStart", "session-start"),
        ("PostToolUse", "post-tool-use"),
        ("Stop", "stop"),
    ] {
        let commands: Vec<&str> = settings["hooks"][event]
            .as_array()
            .expect("matchers")
            .iter()
            .flat_map(|matcher| matcher["hooks"].as_array().expect("hooks"))
            .filter_map(|hook| hook["command"].as_str())
            .filter(|command| command.contains("hiboss hook"))
            .collect();
        assert_eq!(
            commands,
            vec![format!("HIBOSS_PROFILE=claude hiboss hook {label}")]
        );
    }
}
