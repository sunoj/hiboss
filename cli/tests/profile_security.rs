// Exercises credential isolation, v2-only reads and private saves through the real CLI.
// Uses synthetic credentials and isolated HOME/config paths; no external services.
// Dependencies: std::process, std::fs, serde_json.

use serde_json::{Value, json};
use std::{
    fs,
    path::PathBuf,
    process::{Command, Output},
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT: AtomicU64 = AtomicU64::new(0);
struct Sandbox(PathBuf);

impl Sandbox {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "hiboss-profile-security-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).expect("fixture directory");
        Self(root)
    }

    fn run(&self, args: &[&str], env: &[(&str, &str)]) -> Output {
        Command::new(env!("CARGO_BIN_EXE_hiboss"))
            .env_clear()
            .current_dir(&self.0)
            .env("HOME", &self.0)
            .env("XDG_CONFIG_HOME", self.0.join(".config"))
            .env("HIBOSS_CONFIG", self.0.join("config.json"))
            .envs(env.iter().copied())
            .args(args)
            .output()
            .expect("run binary")
    }

    fn write(&self, config: &Value) {
        fs::write(self.0.join("config.json"), config.to_string()).expect("fixture config");
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn config() -> Value {
    json!({"version":2,"server":"https://global.invalid","device_id":"synthetic-device",
        "default_profile":"environment","channel":null,"profiles":{
            "environment":{"key":"synthetic-private-key","server":"https://override.invalid","agent_id":"saved-id","name":"Saved agent"},
            "none":{"key":"wrong-private-key","server":"https://wrong.invalid","agent_id":"other-id","name":"Other agent"}}})
}

#[test]
fn absent_runtime_never_selects_none_and_config_output_masks_keys() {
    let sandbox = Sandbox::new();
    sandbox.write(&config());
    for signals in [
        vec![],
        vec![("CLAUDE_CODE_SESSION_ID", "session")],
        vec![("CLAUDECODE", "0"), ("CLAUDE_CODE_SESSION_ID", "session")],
    ] {
        let output = sandbox.run(&["whoami", "--json"], &signals);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let identity: Value = serde_json::from_slice(&output.stdout).expect("whoami JSON");
        assert_eq!(identity["source_rule"], 4);
        assert_eq!(identity["profile"], "environment");
        assert_eq!(identity["runtime"], "none");
        assert_eq!(identity["server"], "https://override.invalid");
    }
    for args in [
        vec!["config", "get", "key"],
        vec!["config", "list"],
        vec!["whoami"],
    ] {
        let output = sandbox.run(&args, &[]);
        let shown = String::from_utf8_lossy(&output.stdout);
        assert!(output.status.success());
        assert!(!shown.contains("synthetic-private-key"));
        assert!(shown.contains("...-key"), "{shown}");
    }
}

#[test]
fn blank_ephemeral_variables_fail_and_rotation_never_touches_disk() {
    let sandbox = Sandbox::new();
    for values in [
        vec![("HIBOSS_SERVER", "")],
        vec![("HIBOSS_KEY", " ")],
        vec![("HIBOSS_SERVER", ""), ("HIBOSS_KEY", "")],
    ] {
        let output = sandbox.run(&["whoami"], &values);
        assert_eq!(output.status.code(), Some(3));
        assert!(String::from_utf8_lossy(&output.stderr).contains("rule 1"));
        assert!(!sandbox.0.join("config.json").exists());
    }
    let env = [
        ("HIBOSS_SERVER", "https://ephemeral.invalid"),
        ("HIBOSS_KEY", "synthetic-private-key"),
    ];
    for args in [
        vec!["key", "rotate"],
        vec!["config", "set", "channel", "api"],
    ] {
        let output = sandbox.run(&args, &env);
        assert!(!output.status.success());
        assert!(String::from_utf8_lossy(&output.stderr).contains("rule 1"));
        assert_eq!(fs::read_dir(&sandbox.0).expect("directory").count(), 0);
    }
}

#[test]
fn versioned_v1_fields_are_rejected_without_rewriting() {
    let sandbox = Sandbox::new();
    for field in ["key", "server_url", "api_key", "selected_profile"] {
        let mut value = config();
        value[field] = json!("synthetic-private-value");
        sandbox.write(&value);
        let original = fs::read(sandbox.0.join("config.json")).expect("original");
        let output = sandbox.run(&["whoami"], &[]);
        assert_eq!(output.status.code(), Some(1), "field {field}");
        assert!(!String::from_utf8_lossy(&output.stderr).contains("synthetic-private-value"));
        assert_eq!(
            fs::read(sandbox.0.join("config.json")).expect("unchanged"),
            original
        );
    }
}

#[test]
fn saves_preserve_parent_permissions_other_profiles_and_default_server_override() {
    let sandbox = Sandbox::new();
    let original = config();
    sandbox.write(&original);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&sandbox.0, fs::Permissions::from_mode(0o755))
            .expect("parent permissions");
    }
    let output = sandbox.run(&["config", "set", "server", "https://new.invalid"], &[]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stored: Value =
        serde_json::from_slice(&fs::read(sandbox.0.join("config.json")).expect("stored"))
            .expect("JSON");
    assert_eq!(stored["server"], original["server"]);
    assert_eq!(stored["profiles"]["none"], original["profiles"]["none"]);
    assert_eq!(
        stored["profiles"]["environment"]["server"],
        "https://new.invalid"
    );
    assert_eq!(stored["device_id"], original["device_id"]);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            fs::metadata(&sandbox.0)
                .expect("parent")
                .permissions()
                .mode()
                & 0o777,
            0o755
        );
        assert_eq!(
            fs::metadata(sandbox.0.join("config.json"))
                .expect("file")
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }
    assert_eq!(fs::read_dir(&sandbox.0).expect("directory").count(), 2);
    assert!(sandbox.0.join("config.config-lock").is_file());
}

#[test]
fn a_relative_config_override_saves_without_temporary_files() {
    let sandbox = Sandbox::new();
    let relative = sandbox.run(
        &["config", "set", "key", "relative-synthetic-key"],
        &[("HIBOSS_CONFIG", "relative.json")],
    );
    assert!(
        relative.status.success(),
        "{}",
        String::from_utf8_lossy(&relative.stderr)
    );
    assert!(sandbox.0.join("relative.json").is_file());
    assert_eq!(fs::read_dir(&sandbox.0).expect("directory").count(), 2);
    assert!(sandbox.0.join("relative.config-lock").is_file());
}

#[test]
fn clean_home_without_override_reports_rule_four_and_the_platform_path() {
    let sandbox = Sandbox::new();
    let output = Command::new(env!("CARGO_BIN_EXE_hiboss"))
        .env_clear()
        .env("HOME", &sandbox.0)
        .env("XDG_CONFIG_HOME", sandbox.0.join(".config"))
        .args(["whoami", "--json"])
        .output()
        .expect("run clean HOME");
    let error = String::from_utf8_lossy(&output.stderr);
    assert_eq!(output.status.code(), Some(3));
    assert!(error.contains("rule 4"), "{error}");
    assert!(error.contains("hiboss/config.json"), "{error}");
    assert!(output.stdout.is_empty());
    assert_eq!(fs::read_dir(&sandbox.0).expect("directory").count(), 0);
}

#[test]
fn config_reads_show_the_selected_server_before_and_after_an_override() {
    let sandbox = Sandbox::new();
    sandbox.write(&config());
    for server in ["https://override.invalid", "https://new.invalid"] {
        if server.ends_with("new.invalid") {
            assert!(
                sandbox
                    .run(&["config", "set", "server", server], &[])
                    .status
                    .success()
            );
        }
        let get = sandbox.run(&["config", "get", "server"], &[]);
        assert_eq!(String::from_utf8_lossy(&get.stdout).trim(), server);
        let list = sandbox.run(&["config", "list"], &[]);
        assert!(String::from_utf8_lossy(&list.stdout).contains(&format!("server = {server}")));
        let whoami: Value = serde_json::from_slice(&sandbox.run(&["whoami", "--json"], &[]).stdout)
            .expect("identity");
        assert_eq!(whoami["server"], server);
    }
}

#[test]
fn an_explicit_missing_profile_blocks_first_writes_to_missing_or_blank_config() {
    let sandbox = Sandbox::new();
    for blank in [false, true] {
        if blank {
            fs::write(sandbox.0.join("config.json"), "").expect("blank config");
        }
        for field in ["key", "server"] {
            let output = sandbox.run(
                &["config", "set", field, "synthetic-value"],
                &[("HIBOSS_PROFILE", "claude")],
            );
            assert_eq!(output.status.code(), Some(3));
            let error = String::from_utf8_lossy(&output.stderr);
            assert!(error.contains("rule 2"));
            assert!(
                error
                    .contains("profile 'claude' is not set up; run: hiboss setup --profile claude")
            );
            if blank {
                assert_eq!(
                    fs::read(sandbox.0.join("config.json")).expect("unchanged"),
                    b""
                );
            } else {
                assert_eq!(fs::read_dir(&sandbox.0).expect("directory").count(), 0);
            }
        }
    }
}
