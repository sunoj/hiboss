// Tests selected-profile atomic key persistence and recovery using synthetic credentials.
// Exercises RotationConfig without environment or HTTP access; depends on std and serde_json.

use super::*;
use serde_json::{Value, json};
use std::sync::atomic::{AtomicUsize, Ordering};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

struct Fixture(PathBuf);

impl Fixture {
    fn new() -> Self {
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let root =
            std::env::temp_dir().join(format!("hiboss-profile-key-{}-{id}", std::process::id()));
        fs::create_dir_all(&root).expect("create synthetic fixture");
        let path = root.join("config.json");
        let config = json!({"version": 2, "server": "https://hiboss.invalid", "device_id": "test-device",
            "default_profile": "claude", "future": 42, "profiles": {
                "claude": {"key": "other-synthetic-key", "name": "claude-agent"},
                "aid.special": {"key": "old-synthetic-key", "name": "aid-agent", "future": "retained"}}});
        fs::write(&path, config.to_string()).expect("write synthetic config");
        Self(path)
    }

    fn stored(&self) -> Value {
        serde_json::from_slice(&fs::read(&self.0).expect("read fixture")).expect("parse fixture")
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.0.parent().expect("fixture parent"));
    }
}

#[test]
fn rotation_changes_only_selected_profile_and_preserves_unknown_fields() {
    let fixture = Fixture::new();
    let original = fixture.stored();
    let mut storage =
        RotationConfig::open(&fixture.0, "aid.special", "old-synthetic-key").expect("open");
    storage.install("new-synthetic-key").expect("install");
    let mut expected = original;
    expected["profiles"]["aid.special"]["key"] = json!("new-synthetic-key");
    assert_eq!(fixture.stored(), expected);
    assert!(fixture.stored().get("key").is_none());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            fs::metadata(&fixture.0)
                .expect("metadata")
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }
    storage.finish().expect("finish");
    assert!(!storage.backup_path().exists());
}

#[test]
fn rotation_restores_exact_original_bytes_after_install() {
    let fixture = Fixture::new();
    let original = fs::read(&fixture.0).expect("original");
    let mut storage =
        RotationConfig::open(&fixture.0, "aid.special", "old-synthetic-key").expect("open");
    assert_eq!(fs::read(storage.backup_path()).expect("backup"), original);
    storage.install("new-synthetic-key").expect("install");
    storage.restore().expect("restore");
    assert_eq!(fs::read(&fixture.0).expect("restored"), original);
}

#[test]
fn rotation_rejects_missing_mismatched_and_v1_profiles_without_changes() {
    let fixture = Fixture::new();
    let original = fs::read(&fixture.0).expect("original");
    for (profile, key) in [
        ("missing", "old-synthetic-key"),
        ("claude", "old-synthetic-key"),
    ] {
        assert!(RotationConfig::open(&fixture.0, profile, key).is_err());
        assert_eq!(fs::read(&fixture.0).expect("unchanged"), original);
        assert!(!fixture.0.with_extension("key-lock").exists());
        assert!(!fixture.0.with_extension("key-previous").exists());
    }
    fs::write(
        &fixture.0,
        r#"{"server":"https://hiboss.invalid","key":"old-synthetic-key"}"#,
    )
    .expect("v1");
    assert!(RotationConfig::open(&fixture.0, "default", "old-synthetic-key").is_err());
}

#[test]
fn rotation_refuses_external_change_before_install_or_restore() {
    let fixture = Fixture::new();
    let mut storage =
        RotationConfig::open(&fixture.0, "aid.special", "old-synthetic-key").expect("open");
    storage.install("new-synthetic-key").expect("install");
    let changed = b"external change";
    fs::write(&fixture.0, changed).expect("external writer");
    assert!(storage.install("another-key").is_err());
    assert!(storage.restore().is_err());
    assert_eq!(fs::read(&fixture.0).expect("unchanged"), changed);
    assert!(storage.backup_path().exists());
}
