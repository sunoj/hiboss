// Purpose: Shared display helpers for CLI output formatting and inbox grouping.
// Exports: short_id, truncate, color_priority, group_messages, SessionGroup.
// Dependencies: colored.

use colored::Colorize;

/// A group of messages sharing a session key, ordered for display.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionGroup<'a, T> {
    pub key: Option<&'a str>,
    pub title: String,
    pub agent_name: Option<&'a str>,
    pub status: Option<&'a str>,
    pub items: Vec<&'a T>,
}

/// Extracted session fields used to group inbox messages.
#[derive(Debug, Clone, Copy, Default)]
pub struct SessionFields<'a> {
    pub session_id: Option<&'a str>,
    pub session_label: Option<&'a str>,
    pub session_branch: Option<&'a str>,
    pub session_status: Option<&'a str>,
    pub agent_name: Option<&'a str>,
    pub created_at: Option<&'a str>,
}

/// Group messages by session_id, most-recently-active session first (by newest
/// `created_at` within group, descending). Messages without a session_id form a
/// trailing "(no session)" group. Within a group, original order is preserved.
/// Returns groups ready for header rendering.
pub fn group_messages<'a, T>(
    items: &'a [T],
    to_fields: impl Fn(&'a T) -> SessionFields<'a>,
) -> Vec<SessionGroup<'a, T>> {
    let mut grouped: std::collections::HashMap<Option<&'a str>, Vec<&'a T>> =
        std::collections::HashMap::new();
    let mut newest: std::collections::HashMap<Option<&'a str>, Option<&'a str>> =
        std::collections::HashMap::new();
    let mut label: std::collections::HashMap<Option<&'a str>, Option<&'a str>> =
        std::collections::HashMap::new();
    let mut branch: std::collections::HashMap<Option<&'a str>, Option<&'a str>> =
        std::collections::HashMap::new();
    let mut status: std::collections::HashMap<Option<&'a str>, Option<&'a str>> =
        std::collections::HashMap::new();
    let mut agent: std::collections::HashMap<Option<&'a str>, Option<&'a str>> =
        std::collections::HashMap::new();
    let mut seen_keys: Vec<Option<&'a str>> = Vec::new();

    for item in items.iter() {
        let f = to_fields(item);
        let key = f.session_id.filter(|s| !s.is_empty());
        if !grouped.contains_key(&key) {
            seen_keys.push(key);
            newest.insert(key, f.created_at);
            label.insert(key, f.session_label);
            branch.insert(key, f.session_branch);
            status.insert(key, f.session_status);
            agent.insert(key, f.agent_name);
        } else {
            let cur = newest.get(&key).copied().flatten();
            match (cur, f.created_at) {
                (Some(c), Some(n)) if n > c => {
                    newest.insert(key, f.created_at);
                }
                (None, Some(_)) => {
                    newest.insert(key, f.created_at);
                }
                _ => {}
            }
            let a = agent.get(&key).copied().flatten();
            if a.is_none() && f.agent_name.is_some() {
                agent.insert(key, f.agent_name);
            }
        }
        grouped.entry(key).or_default().push(item);
    }

    let mut keyed: Vec<Option<&'a str>> =
        seen_keys.iter().copied().filter(|k| k.is_some()).collect();
    keyed.sort_by(|a, b| {
        let na = newest.get(a).and_then(|o| *o).unwrap_or("");
        let nb = newest.get(b).and_then(|o| *o).unwrap_or("");
        nb.cmp(na)
    });

    let mut order: Vec<Option<&'a str>> = keyed.clone();
    if seen_keys.iter().any(|k| k.is_none()) {
        order.push(None);
    }

    order
        .into_iter()
        .map(|key| {
            let items_out = grouped.remove(&key).unwrap_or_default();
            let l = label.get(&key).copied().flatten();
            let b = branch.get(&key).copied().flatten();
            let s = status.get(&key).copied().flatten();
            let a = agent.get(&key).copied().flatten();
            let title = match (key, l, b) {
                (Some(_), Some(l), _) if !l.is_empty() => l.to_string(),
                (Some(_), _, Some(b)) if !b.is_empty() => b.to_string(),
                (Some(sid), _, _) => short_id(sid),
                (None, _, _) => "(no session)".to_string(),
            };
            SessionGroup {
                key,
                title,
                agent_name: a,
                status: s,
                items: items_out,
            }
        })
        .collect()
}

pub fn short_id(value: &str) -> String {
    value.chars().take(8).collect()
}

pub fn truncate(input: &str, limit: usize) -> String {
    if input.chars().count() <= limit {
        input.to_string()
    } else {
        let truncated: String = input.chars().take(limit - 3).collect();
        format!("{}...", truncated)
    }
}

pub fn unescape_body(input: &str) -> String {
    input.replace("\\n", "\n").replace("\\t", "\t")
}

pub fn color_priority(priority: &str) -> colored::ColoredString {
    match priority {
        "critical" => priority.red().bold(),
        "high" => priority.yellow().bold(),
        "normal" => priority.green(),
        "low" => priority.white(),
        _ => priority.normal(),
    }
}
