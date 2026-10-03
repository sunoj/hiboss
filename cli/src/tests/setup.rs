// Tests the real Claude hook settings implementation and preservation behavior.
// Tests apply_hook_changes, matcher_contains_hiboss, and new_hiboss_matcher.
// Dependencies: serde_json.

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::super::{
        HookAction, apply_hook_changes, matcher_contains_hiboss, new_hiboss_matcher,
    };

    // --- matcher_contains_hiboss tests ---

    #[test]
    fn refreshes_every_managed_hook_and_preserves_neighbor_commands() {
        let mut settings = json!({"theme": "dark", "hooks": {
            "SessionStart": [{"matcher": "", "hooks": [
                {"type": "command", "command": "other-tool check"},
                {"type": "command", "command": "HIBOSS_PROFILE=old hiboss hook session-start", "timeout": 12}
            ]}],
            "Notification": [{"hooks": [{"command": "hiboss hook post-tool-use"}]}]
        }});
        let change = apply_hook_changes(&mut settings, false, None).unwrap();
        assert!(change.changed);
        assert_eq!(settings["theme"], "dark");
        assert_eq!(
            settings["hooks"]["SessionStart"][0]["hooks"][0]["command"],
            "other-tool check"
        );
        assert_eq!(
            settings["hooks"]["SessionStart"][0]["hooks"][1]["command"],
            "HIBOSS_PROFILE=claude hiboss hook session-start"
        );
        assert_eq!(
            settings["hooks"]["SessionStart"][0]["hooks"][1]["timeout"],
            12
        );
        assert_eq!(
            settings["hooks"]["Notification"][0]["hooks"][0]["command"],
            "HIBOSS_PROFILE=claude hiboss hook post-tool-use"
        );
        assert!(
            !apply_hook_changes(&mut settings, false, None)
                .unwrap()
                .changed
        );
    }

    #[test]
    fn removal_preserves_unrelated_commands_in_a_shared_matcher() {
        let mut settings = json!({"hooks": {"Stop": [{"matcher": "", "hooks": [
            {"command": "other-tool finish"}, {"command": "HIBOSS_PROFILE=claude hiboss hook stop"}
        ]}]}});
        apply_hook_changes(&mut settings, true, None).unwrap();
        assert_eq!(
            settings["hooks"]["Stop"][0]["hooks"],
            json!([{"command": "other-tool finish"}])
        );
    }

    #[test]
    fn project_commands_quote_the_directory_and_select_claude() {
        let matcher = new_hiboss_matcher("stop", Some("/tmp/project's ; folder"));
        assert_eq!(
            matcher["hooks"][0]["command"],
            "HIBOSS_PROFILE=claude HIBOSS_PROJECT_DIR='/tmp/project'\\''s ; folder' hiboss hook stop"
        );
    }

    #[test]
    fn matcher_detects_hiboss_hook() {
        let matcher = new_hiboss_matcher("session-start", None);
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
        let m = new_hiboss_matcher("session-start", None);
        assert_eq!(m["matcher"], "");
        let hooks = m["hooks"].as_array().unwrap();
        assert_eq!(hooks.len(), 1);
        assert_eq!(hooks[0]["type"], "command");
        assert_eq!(
            hooks[0]["command"],
            "HIBOSS_PROFILE=claude hiboss hook session-start"
        );
    }

    // --- apply_hook_changes (add) tests ---

    #[test]
    fn add_hooks_to_empty_settings() {
        let mut settings = json!({});
        let change = apply_hook_changes(&mut settings, false, None).unwrap();
        assert!(change.changed);
        assert_eq!(change.action, HookAction::Added);
        let hooks = settings["hooks"].as_object().unwrap();
        assert!(hooks.contains_key("SessionStart"));
        assert!(hooks.contains_key("PostToolUse"));
    }

    #[test]
    fn add_hooks_to_empty_hooks_object() {
        let mut settings = json!({"hooks": {}});
        let change = apply_hook_changes(&mut settings, false, None).unwrap();
        assert!(change.changed);
        assert_eq!(change.action, HookAction::Added);
    }

    #[test]
    fn add_hooks_idempotent_when_already_present() {
        let mut settings = json!({});
        apply_hook_changes(&mut settings, false, None).unwrap();
        let change = apply_hook_changes(&mut settings, false, None).unwrap();
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
        let change = apply_hook_changes(&mut settings, false, None).unwrap();
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
        apply_hook_changes(&mut settings, false, None).unwrap();
        let change = apply_hook_changes(&mut settings, true, None).unwrap();
        assert!(change.changed);
        assert_eq!(change.action, HookAction::Removed);
        // hooks key should be removed entirely
        assert!(settings.get("hooks").is_none());
    }

    #[test]
    fn remove_noop_when_no_hooks() {
        let mut settings = json!({});
        let change = apply_hook_changes(&mut settings, true, None).unwrap();
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
        let change = apply_hook_changes(&mut settings, true, None).unwrap();
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
        apply_hook_changes(&mut settings, false, None).unwrap();
        apply_hook_changes(&mut settings, true, None).unwrap();
        assert!(settings.get("hooks").is_none());
    }
}
