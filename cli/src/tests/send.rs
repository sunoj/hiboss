// Purpose: Test send command request and peer-target formatting behavior.
// Exports: send command unit tests.
// Dependencies: crate::commands::send, serde_json.

use crate::commands::send::{
    SendArgs, broadcast_request, broadcast_result_prefix, format_peer_target,
};
use crate::commands::send_metadata::build_metadata;
use serde_json::Value;

fn args_with_content(content: Option<&str>) -> SendArgs {
    SendArgs {
        priority: "normal".to_owned(),
        channel: None,
        file_url: None,
        file: None,
        message_type: None,
        to: None,
        wait_ack: false,
        broadcast: false,
        task: None,
        summary: None,
        content: content.map(str::to_owned),
        content_file: None,
        files: None,
        branch: None,
        body: "body".to_owned(),
    }
}

#[test]
fn metadata_includes_content() {
    let metadata = build_metadata(&args_with_content(Some("deploy context")))
        .expect("metadata builds")
        .expect("metadata present");
    assert_eq!(
        metadata.get("content"),
        Some(&Value::String("deploy context".to_owned()))
    );
}

#[test]
fn metadata_omits_empty_content() {
    let metadata = build_metadata(&args_with_content(Some(""))).expect("metadata builds");
    assert!(metadata.is_none());
}

#[test]
fn broadcast_result_prefix_names_label_and_short_id() {
    assert_eq!(
        broadcast_result_prefix(Some("smart-router/main"), "aefb4ffd12345678"),
        "Broadcast target smart-router/main (aefb4ffd)"
    );
}

#[test]
fn agent_name_target_falls_back_to_requested_address() {
    assert_eq!(format_peer_target(None, "smart-router"), "smart-router");
}

#[test]
fn resolved_target_uses_nickname_before_label_and_keeps_legacy_output() {
    let mut target = crate::types::SendTarget {
        id: "aefb4ffd12345678".to_owned(),
        label: Some("smart-router/main".to_owned()),
        nickname: Some("otter-2".to_owned()),
    };
    assert_eq!(
        format_peer_target(Some(&target), "main"),
        "otter-2 (aefb4ffd)"
    );
    target.nickname = None;
    assert_eq!(
        format_peer_target(Some(&target), "main"),
        "smart-router/main (aefb4ffd)"
    );
    target.label = None;
    assert_eq!(
        format_peer_target(Some(&target), "main"),
        "aefb4ffd12345678 (aefb4ffd)"
    );
}

#[test]
fn broadcast_request_targets_peer_session_id() {
    let args = args_with_content(None);
    let request = broadcast_request(&args, "broadcast body", None, "peer-session-id");
    assert_eq!(request.body, "broadcast body");
    assert_eq!(request.to.as_deref(), Some("peer-session-id"));
}
