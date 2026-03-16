// Unit tests for types.rs serde roundtrips and config.rs validation logic.
// Tests serialization correctness, Option handling, and Config require_* methods.
// Dependencies: crate::types, crate::config, serde_json.

#[cfg(test)]
mod tests {
    use crate::config::Config;
    use crate::types::{
        Message, MessagesResponse, ReplyRequest, SendRequest, SendResponse, StatusUpdate,
    };
    use serde::de::DeserializeOwned;
    use serde::Serialize;
    use serde_json;
    use std::collections::HashMap;

    fn assert_roundtrip<T>(value: &T)
    where
        T: Serialize + DeserializeOwned,
    {
        let payload = serde_json::to_string(value).expect("serialize");
        let restored = serde_json::from_str::<T>(&payload).expect("deserialize");
        assert_eq!(serde_json::to_value(value).unwrap(), serde_json::to_value(&restored).unwrap());
    }

    fn minimal_message(id: &str) -> Message {
        Message {
            id: id.to_string(),
            agent_id: None,
            agent_name: None,
            direction: None,
            mode: None,
            channel: None,
            body: None,
            status: None,
            reply_to: None,
            priority: None,
            metadata: None,
            created_at: None,
            updated_at: None,
            replies: None,
        }
    }

    #[test]
    fn message_roundtrips_full_fields() {
        let mut metadata = HashMap::new();
        metadata.insert("topic".to_string(), serde_json::json!("hello"));
        let message = Message {
            id: "full".to_string(),
            agent_id: Some("agent-1".to_string()),
            agent_name: Some("Agent".to_string()),
            direction: Some("out".to_string()),
            mode: Some("async".to_string()),
            channel: Some("main".to_string()),
            body: Some("content".to_string()),
            status: Some("sent".to_string()),
            reply_to: Some("root".to_string()),
            priority: Some("high".to_string()),
            metadata: Some(metadata),
            created_at: Some("2026-03-16T00:00:00Z".to_string()),
            updated_at: Some("2026-03-16T00:01:00Z".to_string()),
            replies: None,
        };
        assert_roundtrip(&message);
    }

    #[test]
    fn message_roundtrips_minimal_fields() {
        let message = minimal_message("minimal");
        assert_roundtrip(&message);
    }

    #[test]
    fn message_roundtrips_with_replies() {
        let reply = minimal_message("reply");
        let mut parent = minimal_message("parent");
        parent.replies = Some(vec![reply]);
        parent.metadata = Some({
            let mut info = HashMap::new();
            info.insert("thread".to_string(), serde_json::json!("stack"));
            info
        });
        assert_roundtrip(&parent);
    }

    #[test]
    fn send_request_roundtrips_with_options() {
        let mut metadata = HashMap::new();
        metadata.insert("flag".to_string(), serde_json::json!(true));
        let request = SendRequest {
            body: "lets go".to_string(),
            mode: "async".to_string(),
            priority: "low".to_string(),
            channel: Some("default".to_string()),
            metadata: Some(metadata),
            options: Some(vec!["opt-a".to_string(), "opt-b".to_string()]),
            file_url: None,
        };
        assert_roundtrip(&request);
    }

    #[test]
    fn send_request_roundtrips_without_options() {
        let request = SendRequest {
            body: "plain".to_string(),
            mode: "sync".to_string(),
            priority: "medium".to_string(),
            channel: None,
            metadata: None,
            options: None,
            file_url: None,
        };
        assert_roundtrip(&request);
    }

    #[test]
    fn send_response_roundtrips() {
        let response = SendResponse {
            id: "rsp-1".to_string(),
            status: "ok".to_string(),
            created_at: "2026-03-16T01:00:00Z".to_string(),
        };
        assert_roundtrip(&response);
    }

    #[test]
    fn messages_response_handles_empty_messages() {
        let response = MessagesResponse {
            messages: Vec::new(),
            total: 0,
        };
        assert_roundtrip(&response);
    }

    #[test]
    fn messages_response_handles_multiple_messages() {
        let response = MessagesResponse {
            messages: vec![minimal_message("first"), minimal_message("second")],
            total: 2,
        };
        assert_roundtrip(&response);
    }

    #[test]
    fn status_update_roundtrips() {
        let status = StatusUpdate {
            status: "pending".to_string(),
        };
        assert_roundtrip(&status);
    }

    #[test]
    fn reply_request_roundtrips() {
        let request = ReplyRequest {
            body: "got it".to_string(),
        };
        assert_roundtrip(&request);
    }

    #[test]
    fn config_default_fields_are_none() {
        let cfg = Config::default();
        assert!(cfg.server.is_none());
        assert!(cfg.key.is_none());
        assert!(cfg.channel.is_none());
    }

    #[test]
    fn config_require_server_behavior() {
        let mut cfg = Config::default();
        assert!(cfg.require_server().is_err());
        cfg.server = Some("https://example.com".to_string());
        assert_eq!(cfg.require_server().unwrap(), "https://example.com");
    }

    #[test]
    fn config_require_key_behavior() {
        let mut cfg = Config::default();
        assert!(cfg.require_key().is_err());
        cfg.key = Some("secret".to_string());
        assert_eq!(cfg.require_key().unwrap(), "secret");
    }

    #[test]
    fn config_roundtrips_via_json() {
        let cfg = Config {
            server: Some("https://a".to_string()),
            key: Some("abc".to_string()),
            channel: Some("chan".to_string()),
        };
        let payload = serde_json::to_string(&cfg).expect("serialize");
        let restored: Config = serde_json::from_str(&payload).expect("deserialize");
        assert_eq!(cfg.server, restored.server);
        assert_eq!(cfg.key, restored.key);
        assert_eq!(cfg.channel, restored.channel);
    }
}
