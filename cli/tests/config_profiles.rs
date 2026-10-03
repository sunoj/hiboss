// Purpose: Exercise credential selection and migration through the CLI binary.
// Exports: isolated end-to-end config and whoami tests.
// Dependencies: std::process and serde_json; never inherits operator identity.

use serde_json::{Value, json};
use std::{
    fs,
    path::PathBuf,
    process::{Command, Output},
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT: AtomicU64 = AtomicU64::new(0);

struct Sandbox {
    root: PathBuf,
}

impl Sandbox {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "hiboss-profiles-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        Self { root }
    }

    fn path(&self) -> PathBuf {
        self.root.join("config.json")
    }

    fn run(&self, args: &[&str], env: &[(&str, &str)]) -> Output {
        let mut command = Command::new(env!("CARGO_BIN_EXE_hiboss"));
        command
            .env_clear()
            .env("HOME", &self.root)
            .env("HIBOSS_CONFIG", self.path())
            .args(args);
        for (name, value) in env {
            command.env(name, value);
        }
        command.output().unwrap()
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.root).unwrap();
    }
}

fn identity(output: &Output) -> Value {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}

fn v2() -> Value {
    json!({"version":2,"server":"https://global.test","device_id":"d_1",
        "default_profile":"default","channel":null,"profiles":{
            "default":{"key":"hb_default","name":"Default"},
            "claude":{"key":"hb_claude","name":"Claude","server":"https://claude.test"},
            "aid":{"key":"hb_aid","name":"Aid"}}})
}

#[test]
fn rule_one_never_reads_or_writes_even_malformed_or_absent_config() {
    let box_ = Sandbox::new();
    fs::write(box_.path(), "{broken SECRET").unwrap();
    let original = fs::read(box_.path()).unwrap();
    let result = identity(&box_.run(
        &["whoami", "--json"],
        &[
            ("HIBOSS_SERVER", "https://ephemeral.test"),
            ("HIBOSS_KEY", "hb_ephemeral"),
            ("HIBOSS_PROFILE", "absent"),
            ("AID_TASK_ID", "task"),
        ],
    ));
    assert_eq!(result["source_rule"], 1);
    assert_eq!(result["agent_name"], Value::Null);
    assert_eq!(result["key"], "...eral");
    assert_eq!(fs::read(box_.path()).unwrap(), original);
    fs::remove_file(box_.path()).unwrap();
    assert_eq!(
        identity(&box_.run(
            &["whoami", "--json"],
            &[
                ("HIBOSS_SERVER", "https://ephemeral.test"),
                ("HIBOSS_KEY", "key")
            ]
        ))["source_rule"],
        1
    );
    assert!(!box_.path().exists());
}

#[test]
fn partial_environment_pair_names_missing_variable_and_rule_one() {
    let box_ = Sandbox::new();
    for (provided, missing) in [
        ("HIBOSS_SERVER", "HIBOSS_KEY"),
        ("HIBOSS_KEY", "HIBOSS_SERVER"),
    ] {
        let output = box_.run(&["whoami"], &[(provided, "value")]);
        let error = String::from_utf8_lossy(&output.stderr);
        assert!(!output.status.success());
        assert!(
            error.contains("rule 1") && error.contains(missing),
            "{error}"
        );
        assert!(!box_.path().exists());
    }
}

#[test]
fn explicit_profile_rule_two_and_missing_profile_exit_three() {
    let box_ = Sandbox::new();
    fs::write(box_.path(), v2().to_string()).unwrap();
    let result = identity(&box_.run(
        &["whoami", "--json"],
        &[("HIBOSS_PROFILE", "claude"), ("AID_TASK_ID", "task")],
    ));
    assert_eq!(result["source_rule"], 2);
    assert_eq!(result["server"], "https://claude.test");
    assert_eq!(result["agent_name"], "Claude");
    let output = box_.run(&["whoami"], &[("HIBOSS_PROFILE", "missing")]);
    assert_eq!(output.status.code(), Some(3));
    assert!(
        String::from_utf8_lossy(&output.stderr)
            .contains("profile 'missing' is not set up; run: hiboss setup --profile missing")
    );
}

#[test]
fn runtime_rule_three_precedes_default_and_falls_back_to_rule_four() {
    let box_ = Sandbox::new();
    fs::write(box_.path(), v2().to_string()).unwrap();
    let aid = identity(&box_.run(
        &["whoami", "--json"],
        &[("CLAUDECODE", "1"), ("AID_TASK_ID", "task")],
    ));
    assert_eq!(aid["profile"], "aid");
    assert_eq!(aid["source_rule"], 3);
    assert_eq!(aid["runtime"], "aid");
    let claude = identity(&box_.run(
        &["whoami", "--json"],
        &[("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "s")],
    ));
    assert_eq!(claude["profile"], "claude");
    let fallback = identity(&box_.run(&["whoami", "--json"], &[("CODEX_THREAD_ID", "c")]));
    assert_eq!(fallback["profile"], "default");
    assert_eq!(fallback["source_rule"], 4);
    assert_eq!(fallback["runtime"], "none");
}

#[test]
fn clean_home_reports_rule_four_and_migration_saves_private_v2_only() {
    let box_ = Sandbox::new();
    let empty = box_.run(&["whoami"], &[]);
    assert!(String::from_utf8_lossy(&empty.stderr).contains("rule 4"));
    assert!(!box_.path().exists());
    fs::write(
        box_.path(),
        r#"{"server":"https://old.test","key":"hb_old","channel":"api"}"#,
    )
    .unwrap();
    let migrated = identity(&box_.run(&["whoami", "--json"], &[]));
    assert_eq!(migrated["profile"], "default");
    assert_eq!(migrated["source_rule"], 4);
    let saved: Value = serde_json::from_slice(&fs::read(box_.path()).unwrap()).unwrap();
    assert_eq!(saved["version"], 2);
    assert_eq!(saved["profiles"]["default"]["key"], "hb_old");
    assert!(saved.get("key").is_none());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            fs::metadata(box_.path()).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
    fs::write(
        box_.path(),
        r#"{"server":"https://old.test","key":"hb_old","unknown":1}"#,
    )
    .unwrap();
    assert!(!box_.run(&["whoami"], &[]).status.success());
}

#[test]
fn selected_profile_setter_updates_only_its_credential() {
    let box_ = Sandbox::new();
    fs::write(box_.path(), v2().to_string()).unwrap();
    let output = box_.run(
        &["config", "set", "key", "hb_rotated"],
        &[("HIBOSS_PROFILE", "claude")],
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let saved: Value = serde_json::from_slice(&fs::read(box_.path()).unwrap()).unwrap();
    assert_eq!(saved["profiles"]["claude"]["key"], "hb_rotated");
    assert_eq!(saved["profiles"]["default"]["key"], "hb_default");
    assert_eq!(saved["profiles"]["aid"]["key"], "hb_aid");
    assert!(saved.get("key").is_none());
}

#[test]
fn malformed_config_error_never_quotes_secret() {
    let box_ = Sandbox::new();
    fs::write(box_.path(), r#"{"version":2,"default_profile":"default","profiles":{"default":{"key":"synthetic-secret"}},"server":4}"#).unwrap();
    let output = box_.run(&["whoami"], &[]);
    let error = String::from_utf8_lossy(&output.stderr);
    assert!(!output.status.success());
    assert!(error.contains("not valid hiboss configuration"), "{error}");
    assert!(!error.contains("synthetic-secret"), "{error}");
}
