// Purpose: Identify the supported agent runtime from process environment.
// Exports: RuntimeIdentity, detection for credential profile selection, DispatchedAsk.
// Dependencies: std::env and thiserror.

/// `hiboss ask` refused because a dispatched agent's questions go to its dispatcher.
#[derive(Debug, thiserror::Error)]
#[error("dispatched agents cannot ask the boss; return the question to your dispatcher")]
pub struct DispatchedAsk;

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
        if let Some(session_key) = get("CODEX_THREAD_ID")
            .filter(|value| !value.trim().is_empty())
            .or_else(|| get("CODEX_SESSION_ID").filter(|value| !value.trim().is_empty()))
        {
            return Self {
                runtime: "codex".into(),
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

    fn check(values: &[(&str, &str)], runtime: &str, session_key: &str) {
        assert_eq!(detect(values), RuntimeIdentity {
            runtime: runtime.into(),
            session_key: session_key.into(),
        }, "{values:?}");
    }

    #[test]
    fn aid_precedes_claude_and_uses_task_id() {
        for values in [
            vec![("AID_TASK_ID", "task-1"), ("CLAUDECODE", "1")],
            vec![("AID_TASK_ID", "task-1"), ("CLAUDECODE", "1"),
                ("CODEX_THREAD_ID", "thread"), ("CODEX_SESSION_ID", "session")],
        ] {
            check(&values, "aid", "task-1");
        }
    }

    #[test]
    fn claude_uses_session_id_or_default() {
        for (values, key) in [
            (vec![("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", "session-1")], "session-1"),
            (vec![("CLAUDECODE", "1")], "default"),
            (vec![("CLAUDECODE", "1"), ("CLAUDE_CODE_SESSION_ID", " \t\n")], "default"),
            (vec![("AID_TASK_ID", " "), ("CLAUDECODE", "1"), ("CODEX_THREAD_ID", "thread")], "default"),
        ] {
            check(&values, "claude", key);
        }
    }

    #[test]
    fn unsupported_and_blank_signals_are_not_detected() {
        for values in [
            vec![("CLAUDE_CODE_SESSION_ID", "id")],
            vec![("CLAUDECODE", "0"), ("CLAUDE_CODE_SESSION_ID", "id")],
            vec![("AID_TASK_ID", " "), ("CODEX_THREAD_ID", " ")],
            vec![],
        ] {
            check(&values, "none", "default");
        }
    }

    #[test]
    fn codex_uses_the_thread_or_session_id_without_collapsing_to_default() {
        for signal in ["CODEX_THREAD_ID", "CODEX_SESSION_ID"] {
            check(&[(signal, "codex-1")], "codex", "codex-1");
        }
        for (values, key) in [
            (vec![("CODEX_THREAD_ID", " "), ("CODEX_SESSION_ID", "s")], "s"),
            (vec![("CODEX_THREAD_ID", "thread"), ("CODEX_SESSION_ID", "session")], "thread"),
            (vec![("CODEX_THREAD_ID", ""), ("CODEX_SESSION_ID", " session ")], " session "),
            (vec![("AID_TASK_ID", " "), ("CLAUDECODE", "0"), ("CODEX_THREAD_ID", "thread")], "thread"),
        ] {
            check(&values, "codex", key);
        }
    }
}
