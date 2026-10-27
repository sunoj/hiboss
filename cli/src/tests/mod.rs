// Purpose: Test module root aggregating all CLI test files.
// Exports: test submodules and explicit message fixtures.
// Dependencies: test submodules.

mod ask;
mod config_recovery;
mod helpers;
mod inbox;
mod send;
mod types_config;

pub(crate) fn message(id: String) -> crate::types::Message {
    crate::types::Message {
        id,
        agent_id: None,
        agent_name: None,
        direction: None,
        mode: None,
        channel: None,
        body: None,
        status: None,
        reply_to: None,
        priority: None,
        message_type: None,
        metadata: None,
        created_at: None,
        updated_at: None,
        session_id: None,
        target_agent_id: None,
        target_session_id: None,
        session_label: None,
        session_branch: None,
        session_status: None,
        replies: None,
    }
}
