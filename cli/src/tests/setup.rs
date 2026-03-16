// Unit tests for setup.rs hook configuration JSON manipulation.
// Tests apply_hook_changes, matcher_contains_hiboss, and new_hiboss_matcher.
// Dependencies: serde_json.

#[cfg(test)]
mod tests {
    use serde_json::{json, Map, Value};

    const EVENT_COMMANDS: &[(&str, &str)] = &[
        ("SessionStart", "session-start"),
        ("PostToolUse", "post-tool-use"),
        ("Stop", "stop"),
    ];

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum HookAction {
        Added,
        Removed,
        None,
    }

    #[derive(Debug)]
    struct HookChange {
        changed: bool,
        action: HookAction,
    }

    impl Default for HookChange {
        fn default() -> Self {
            Self {
                changed: false,
                action: HookAction::None,
            }
        }
    }

    // Copied from setup.rs:180
    fn matcher_contains_hiboss(value: &Value) -> bool {
        value
            .get("hooks")
            .and_then(Value::as_array)
            .map(|hooks| {
                hooks.iter().any(|hook| {
                    hook.get("command")
                        .and_then(Value::as_str)
                        .map(|cmd| cmd.contains("hiboss hook"))
                        .unwrap_or(false)
                })
            })
            .unwrap_or(false)
    }

    // Copied from setup.rs:196
    fn new_hiboss_matcher(command_label: &str) -> Value {
        let mut hook_obj = Map::new();
        hook_obj.insert("type".to_string(), Value::String("command".to_string()));
        hook_obj.insert(
            "command".to_string(),
            Value::String(format!("hiboss hook {}", command_label)),
        );
        let mut matcher_obj = Map::new();
        matcher_obj.insert("matcher".to_string(), Value::String(String::new()));
        matcher_obj.insert(
            "hooks".to_string(),
            Value::Array(vec![Value::Object(hook_obj)]),
        );
        Value::Object(matcher_obj)
    }

    // Copied from setup.rs:109
    fn apply_hook_changes(
        settings: &mut Value,
        remove: bool,
    ) -> Result<HookChange, Box<dyn std::error::Error>> {
        let root = settings
            .as_object_mut()
            .ok_or("settings.json must contain an object")?;

        if remove {
            if let Some(hooks_value) = root.get_mut("hooks") {
                if !hooks_value.is_object() {
                    return Err("hooks must be an object".into());
                }
                let mut change = HookChange::default();
                let mut drop_hooks = false;
                {
                    let hooks_map = hooks_value.as_object_mut().unwrap();
                    let mut to_remove = Vec::new();
                    for (event, _) in EVENT_COMMANDS {
                        if let Some(event_value) = hooks_map.get_mut(*event) {
                            let arr = event_value
                                .as_array_mut()
                                .ok_or_else(|| format!("hooks.{} must be an array", event))?;
                            let original_len = arr.len();
                            arr.retain(|matcher| !matcher_contains_hiboss(matcher));
                            if arr.len() != original_len {
                                change.changed = true;
                                change.action = HookAction::Removed;
                            }
                            if arr.is_empty() {
                                to_remove.push(event.to_string());
                            }
                        }
                    }
                    for event in to_remove {
                        hooks_map.remove(&event);
                    }
                    if hooks_map.is_empty() {
                        drop_hooks = true;
                    }
                }
                if drop_hooks {
                    root.remove("hooks");
                }
                return Ok(change);
            }
            return Ok(HookChange::default());
        }

        let hooks_value = root
            .entry("hooks")
            .or_insert_with(|| Value::Object(Map::new()));
        if !hooks_value.is_object() {
            return Err("hooks must be an object".into());
        }
        let mut change = HookChange::default();
        {
            let hooks_map = hooks_value.as_object_mut().unwrap();
            for (event, command_label) in EVENT_COMMANDS {
                let entry = hooks_map
                    .entry(event.to_string())
                    .or_insert_with(|| Value::Array(vec![]));
                let arr = entry
                    .as_array_mut()
                    .ok_or_else(|| format!("hooks.{} must be an array", event))?;
                if arr.iter().any(matcher_contains_hiboss) {
                    continue;
                }
                arr.push(new_hiboss_matcher(command_label));
                change.changed = true;
                change.action = HookAction::Added;
            }
        }
        Ok(change)
    }

    // --- matcher_contains_hiboss tests ---

    #[test]
    fn matcher_detects_hiboss_hook() {
        let matcher = new_hiboss_matcher("session-start");
        assert!(matcher_contains_hiboss(&matcher));
    }

    #[test]
    fn matcher_rejects_non_hiboss() {
        let matcher = json!({
            "matcher": "",
            "hooks": [{"type": "command", "command": "some-other-tool run"}]
        });
        assert!(!matcher_contains_hiboss(&matcher));
    }

    #[test]
    fn matcher_rejects_empty_object() {
        assert!(!matcher_contains_hiboss(&json!({})));
    }

    #[test]
    fn matcher_rejects_missing_hooks_array() {
        assert!(!matcher_contains_hiboss(&json!({"matcher": ""})));
    }

    // --- new_hiboss_matcher tests ---

    #[test]
    fn new_matcher_has_correct_structure() {
        let m = new_hiboss_matcher("session-start");
        assert_eq!(m["matcher"], "");
        let hooks = m["hooks"].as_array().unwrap();
        assert_eq!(hooks.len(), 1);
        assert_eq!(hooks[0]["type"], "command");
        assert_eq!(hooks[0]["command"], "hiboss hook session-start");
    }

    #[test]
    fn new_matcher_for_stop() {
        let m = new_hiboss_matcher("stop");
        assert_eq!(m["hooks"][0]["command"], "hiboss hook stop");
    }

    // --- apply_hook_changes (add) tests ---

    #[test]
    fn add_hooks_to_empty_settings() {
        let mut settings = json!({});
        let change = apply_hook_changes(&mut settings, false).unwrap();
        assert!(change.changed);
        assert_eq!(change.action, HookAction::Added);
        let hooks = settings["hooks"].as_object().unwrap();
        assert!(hooks.contains_key("SessionStart"));
        assert!(hooks.contains_key("PostToolUse"));
        assert!(hooks.contains_key("Stop"));
    }

    #[test]
    fn add_hooks_to_empty_hooks_object() {
        let mut settings = json!({"hooks": {}});
        let change = apply_hook_changes(&mut settings, false).unwrap();
        assert!(change.changed);
        assert_eq!(change.action, HookAction::Added);
    }

    #[test]
    fn add_hooks_idempotent_when_already_present() {
        let mut settings = json!({});
        apply_hook_changes(&mut settings, false).unwrap();
        let change = apply_hook_changes(&mut settings, false).unwrap();
        assert!(!change.changed);
        assert_eq!(change.action, HookAction::None);
    }

    #[test]
    fn add_hooks_preserves_existing_non_hiboss() {
        let existing = json!({
            "hooks": {
                "SessionStart": [
                    {"matcher": "", "hooks": [{"type": "command", "command": "my-tool check"}]}
                ]
            }
        });
        let mut settings = existing;
        let change = apply_hook_changes(&mut settings, false).unwrap();
        assert!(change.changed);
        // SessionStart should now have 2 matchers (original + hiboss)
        let session_hooks = settings["hooks"]["SessionStart"].as_array().unwrap();
        assert_eq!(session_hooks.len(), 2);
        // Original matcher preserved
        assert_eq!(session_hooks[0]["hooks"][0]["command"], "my-tool check");
    }

    // --- apply_hook_changes (remove) tests ---

    #[test]
    fn remove_hiboss_hooks() {
        let mut settings = json!({});
        apply_hook_changes(&mut settings, false).unwrap();
        let change = apply_hook_changes(&mut settings, true).unwrap();
        assert!(change.changed);
        assert_eq!(change.action, HookAction::Removed);
        // hooks key should be removed entirely
        assert!(settings.get("hooks").is_none());
    }

    #[test]
    fn remove_noop_when_no_hooks() {
        let mut settings = json!({});
        let change = apply_hook_changes(&mut settings, true).unwrap();
        assert!(!change.changed);
        assert_eq!(change.action, HookAction::None);
    }

    #[test]
    fn remove_preserves_non_hiboss_hooks() {
        let mut settings = json!({
            "hooks": {
                "SessionStart": [
                    {"matcher": "", "hooks": [{"type": "command", "command": "my-tool check"}]},
                    {"matcher": "", "hooks": [{"type": "command", "command": "hiboss hook session-start"}]}
                ],
                "PostToolUse": [
                    {"matcher": "", "hooks": [{"type": "command", "command": "hiboss hook post-tool-use"}]}
                ]
            }
        });
        let change = apply_hook_changes(&mut settings, true).unwrap();
        assert!(change.changed);
        assert_eq!(change.action, HookAction::Removed);
        // SessionStart should keep non-hiboss matcher
        let session_hooks = settings["hooks"]["SessionStart"].as_array().unwrap();
        assert_eq!(session_hooks.len(), 1);
        assert_eq!(session_hooks[0]["hooks"][0]["command"], "my-tool check");
        // PostToolUse removed entirely (was only hiboss)
        assert!(settings["hooks"].get("PostToolUse").is_none());
    }

    #[test]
    fn remove_drops_hooks_key_when_only_hiboss() {
        let mut settings = json!({});
        apply_hook_changes(&mut settings, false).unwrap();
        apply_hook_changes(&mut settings, true).unwrap();
        assert!(settings.get("hooks").is_none());
    }
}
