// Verifies stale snapshots cannot discard concurrent enrollment or rotation credentials.
// Runs config library transactions in an isolated subprocess without mutating process env.
// Dependencies: config v2 API, std subprocess/filesystem, and synthetic JSON fixtures.

use hiboss::config::{self, Config};
use serde_json::json;
use std::{fs, process::Command};

#[test]
fn stale_saves_preserve_new_profiles_and_unmodified_rotated_keys() {
    if std::env::var_os("HIBOSS_ATOMIC_WORKER").is_some() {
        check_stale_save();
        return;
    }
    let path = std::env::temp_dir().join(format!("hiboss-atomic-{}", std::process::id()));
    fs::create_dir_all(&path).expect("sandbox");
    let result = Command::new(std::env::current_exe().expect("test binary"))
        .args([
            "--exact",
            "stale_saves_preserve_new_profiles_and_unmodified_rotated_keys",
            "--nocapture",
        ])
        .env_clear()
        .env("HIBOSS_ATOMIC_WORKER", "1")
        .env("HIBOSS_CONFIG", path.join("config.json"))
        .output()
        .expect("isolated worker");
    fs::remove_dir_all(path).expect("cleanup");
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stdout)
    );
}

fn check_stale_save() {
    let path = config::config_path();
    let original = json!({"version":2,"server":"https://synthetic.example","default_profile":"aid",
        "profiles":{"aid":{"key":"synthetic-original-key","agent_id":"synthetic-agent","name":"synthetic-name"}}});
    fs::write(&path, original.to_string()).expect("original config");
    let mut stale: Config = config::load_config().expect("stale snapshot");
    let mut latest = original;
    latest["device_id"] = json!("synthetic-device");
    latest["profiles"]["aid"]["key"] = json!("synthetic-rotated-key");
    latest["profiles"]["codex"] = json!({"key":"synthetic-new-key","agent_id":"synthetic-codex","name":"synthetic-codex-name"});
    fs::write(&path, latest.to_string()).expect("newer credentials");
    stale.channel = Some("discord".into());
    config::save_config(&stale).expect("stale channel update");
    let stored = config::load_saved_config().expect("saved config");
    assert_eq!(
        stored.profiles["aid"].key.as_deref(),
        Some("synthetic-rotated-key")
    );
    assert_eq!(
        stored.profiles["codex"].key.as_deref(),
        Some("synthetic-new-key")
    );
    assert_eq!(stored.device_id.as_deref(), Some("synthetic-device"));
    assert_eq!(stored.channel.as_deref(), Some("discord"));
}
