// Purpose: Identify the supported agent runtime from process environment.
// Exports: RuntimeIdentity, detection for credential profile selection, DispatchedAsk.
// Dependencies: std::env only.

/// `hiboss ask` refused because a dispatched agent's questions go to its dispatcher.
#[derive(Debug)]
pub struct DispatchedAsk;

impl std::fmt::Display for DispatchedAsk {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("dispatched agents cannot ask the boss; return the question to your dispatcher")
    }
}

impl std::error::Error for DispatchedAsk {}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RuntimeIdentity {
    pub runtime: String,
    pub session_key: String,
}

impl RuntimeIdentity {
    pub fn detect() -> Self {
        Self::from_env(|name| std::env::var(name).ok())
    }

    /// A dispatched (aid) agent reports to its dispatcher and never blocks on the boss.
    pub fn is_dispatched(&self) -> bool {
        self.runtime == "aid"
    }

    fn from_env(get: impl Fn(&str) -> Option<String>) -> Self {
        let aid = get("AID_TASK_ID").filter(|value| !value.trim().is_empty());
        if let Some(session_key) = aid {
            return Self {
                runtime: "aid".into(),
                session_key,
            };
        }
        if get("CLAUDECODE").as_deref() == Some("1") {
            let session_key = get("CLAUDE_CODE_SESSION_ID")
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| "default".into());
            return Self {
                runtime: "claude".into(),
                session_key,
            };
        }
        Self {
            runtime: "none".into(),
            session_key: "default".into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn detect(values: &[(&str, &str)]) -> RuntimeIdentity {
        let env: HashMap<_, _> = values.iter().copied().collect();
        RuntimeIdentity::from_env(|name| env.get(name).map(|value| (*value).into()))
    }

    #[test]
    fn aid_precedes_claude_and_uses_task_id() {
        assert_eq!(
            detect(&[("AID_TASK_ID", "task-1"), ("CLAUDECODE", "1")]),
            RuntimeIdentity {
                runtime: "aid".into(),
                session_key: "task-1".into()
            }
        );
    }

    #[test]
    fn claude_uses_session_id_or_default() {
        assert_eq!(
            detect(&[("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "session-1")]).session_key,
            "session-1"
        );
        assert_eq!(
            detect(&[("CLAUDECODE", "1")]),
            RuntimeIdentity {
                runtime: "claude".into(),
                session_key: "default".into()
            }
        );
    }

    #[test]
    fn unsupported_and_blank_signals_are_not_detected() {
        for values in [
            vec![("CLAUDE_CODE_SESSION_ID", "id")],
            vec![("CLAUDECODE", "0"), ("CLAUDE_CODE_SESSION_ID", "id")],
        ] {
            assert_eq!(detect(&values).runtime, "none");
        }
        assert_eq!(
            detect(&[("AID_TASK_ID", " "), ("CODEX_THREAD_ID", "id")]),
            RuntimeIdentity {
                runtime: "none".into(),
                session_key: "default".into()
            }
        );
    }
}
