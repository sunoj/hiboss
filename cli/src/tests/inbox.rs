// Unit tests for inbox session grouping logic (group_messages).
// Dependencies: crate::helpers.

#[cfg(test)]
mod tests {
    use crate::helpers::{SessionFields, group_messages};

    #[derive(Debug, Clone)]
    struct Msg {
        sid: Option<String>,
        label: Option<String>,
        branch: Option<String>,
        status: Option<String>,
        agent: Option<String>,
        created: Option<String>,
        body: String,
    }

    fn m(body: &str, created: &str) -> Msg {
        Msg {
            sid: None,
            label: None,
            branch: None,
            status: None,
            agent: None,
            created: Some(created.to_string()),
            body: body.to_string(),
        }
    }

    fn extract(i: &Msg) -> SessionFields<'_> {
        SessionFields {
            session_id: i.sid.as_deref(),
            session_label: i.label.as_deref(),
            session_branch: i.branch.as_deref(),
            session_status: i.status.as_deref(),
            agent_name: i.agent.as_deref(),
            created_at: i.created.as_deref(),
        }
    }

    #[test]
    fn groups_by_session_id_preserving_message_order() {
        let mut a = m("a1", "2024-01-01T00:00:00Z");
        a.sid = Some("s-a".into());
        let mut b = m("b1", "2024-01-01T00:00:01Z");
        b.sid = Some("s-a".into());
        let mut c = m("c1", "2024-01-01T00:00:02Z");
        c.sid = Some("s-b".into());
        let items = vec![a, b, c];
        let groups = group_messages(&items, extract);
        assert_eq!(groups.len(), 2);
        assert_eq!(groups[0].items.len(), 1); // s-b (newest)
        assert_eq!(groups[0].items[0].body, "c1");
        assert_eq!(groups[1].items.len(), 2); // s-a (older)
        assert_eq!(groups[1].items[0].body, "a1");
        assert_eq!(groups[1].items[1].body, "b1");
    }

    #[test]
    fn newest_at_descending_across_groups() {
        let mut old = m("old", "2024-01-01T00:00:00Z");
        old.sid = Some("s-old".into());
        let mut mid = m("mid", "2024-01-02T00:00:00Z");
        mid.sid = Some("s-mid".into());
        let mut new = m("new", "2024-01-03T00:00:00Z");
        new.sid = Some("s-new".into());
        let items = vec![mid, old, new];
        let groups = group_messages(&items, extract);
        assert_eq!(groups.len(), 3);
        assert_eq!(groups[0].key, Some("s-new"));
        assert_eq!(groups[1].key, Some("s-mid"));
        assert_eq!(groups[2].key, Some("s-old"));
    }

    #[test]
    fn no_session_group_is_trailing() {
        let mut k = m("k", "2024-01-05T00:00:00Z");
        k.sid = Some("s-k".into());
        let none = m("none", "2024-01-01T00:00:00Z");
        let none2 = m("none2", "2024-01-06T00:00:00Z");
        let items = vec![none, k.clone(), none2];
        let groups = group_messages(&items, extract);
        assert_eq!(groups.len(), 2);
        assert_eq!(groups[1].key, None);
        assert_eq!(groups[1].items.len(), 2);
        assert_eq!(groups[1].title, "(no session)");
    }

    #[test]
    fn title_prefers_label_then_branch_then_short_id() {
        let mut l = m("l", "2024-01-01T00:00:00Z");
        l.sid = Some("abcdefgh12345".into());
        l.label = Some("feat/login".into());
        l.branch = Some("main".into());
        let items = vec![l];
        let groups = group_messages(&items, extract);
        assert_eq!(groups[0].title, "feat/login");

        let mut b_only = m("b", "2024-01-01T00:00:00Z");
        b_only.sid = Some("abcdefgh12345".into());
        b_only.branch = Some("feat/x".into());
        let items_b = vec![b_only];
        let g2 = group_messages(&items_b, extract);
        assert_eq!(g2[0].title, "feat/x");

        let mut id_only = m("i", "2024-01-01T00:00:00Z");
        id_only.sid = Some("abcdefgh12345".into());
        let items_i = vec![id_only];
        let g3 = group_messages(&items_i, extract);
        assert_eq!(g3[0].title, "abcdefgh");
    }

    #[test]
    fn empty_session_id_treated_as_no_session() {
        let mut e = m("e", "2024-01-01T00:00:00Z");
        e.sid = Some("".into());
        let items = vec![e];
        let groups = group_messages(&items, extract);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].key, None);
        assert_eq!(groups[0].title, "(no session)");
    }

    #[test]
    fn agent_and_status_captured_in_group() {
        let mut g = m("x", "2024-01-01T00:00:00Z");
        g.sid = Some("s-x".into());
        g.agent = Some("claude-a".into());
        g.status = Some("working".into());
        let items = vec![g];
        let groups = group_messages(&items, extract);
        assert_eq!(groups[0].agent_name, Some("claude-a"));
        assert_eq!(groups[0].status, Some("working"));
    }

    #[test]
    fn empty_items_returns_empty_groups() {
        let items: Vec<Msg> = vec![];
        let groups = group_messages(&items, extract);
        assert!(groups.is_empty());
    }

    #[test]
    fn newest_uses_max_created_per_group() {
        let mut a1 = m("a1", "2024-01-01T00:00:00Z");
        a1.sid = Some("s-a".into());
        let mut a2 = m("a2", "2024-03-01T00:00:00Z");
        a2.sid = Some("s-a".into());
        let mut a3 = m("a3", "2024-02-01T00:00:00Z");
        a3.sid = Some("s-a".into());
        let mut b1 = m("b1", "2024-02-15T00:00:00Z");
        b1.sid = Some("s-b".into());
        // s-a's newest = 03-01, s-b's newest = 02-15 -> s-a should be first.
        let items = vec![a1, a2, a3, b1];
        let groups = group_messages(&items, extract);
        assert_eq!(groups[0].key, Some("s-a"));
        assert_eq!(groups[1].key, Some("s-b"));
        assert_eq!(groups[0].items.len(), 3);
    }
}
