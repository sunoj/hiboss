// Publication validator regression tests and shared fixture cases.
// Dependencies: parent validator and serde_json.
use super::*;

    fn publication() -> Value {
        serde_json::json!({"protocolVersion":2,"targetBossId":"boss_1","taskKey":"task_1","sessionId":"session_1","title":"Panel","catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Metric","props":{"label":"Done","value":{"$state":"/task/done"}},"children":[]}}},"stateSchema":{"type":"object","properties":{"task":{"type":"object","properties":{"done":{"type":"integer"}},"required":["done"],"additionalProperties":false}},"required":["task"],"additionalProperties":false},"initialState":{"task":{"done":0}}})
    }

    #[test]
    fn accepts_valid_publication() { assert_eq!(validate_publication(&publication()), Ok(())); }

    #[test]
    fn accepts_server_resolved_target_and_session() {
        let mut value = publication();
        value.as_object_mut().expect("publication object").remove("targetBossId");
        value.as_object_mut().expect("publication object").remove("sessionId");
        assert_eq!(validate_publication(&value), Ok(()));
    }

    #[test]
    fn reports_unknown_component_with_pointer() { let mut value = publication(); value["spec"]["elements"]["main"]["type"] = Value::String("Unknown".into()); let issue = validate_publication(&value).expect_err("invalid component"); assert_eq!(issue.path, "/spec/elements/main/type"); }

    #[test]
    fn rejects_undeclared_binding_path() { let mut value = publication(); value["spec"]["elements"]["main"]["props"]["value"]["$state"] = Value::String("/task/missing".into()); let issue = validate_publication(&value).expect_err("invalid binding"); assert_eq!(issue.path, "/spec/elements/main/props/value/$state"); }

    #[test]
    fn rejects_cycle() { let mut value = publication(); value["spec"]["elements"]["main"]["children"] = serde_json::json!(["main"]); let issue = validate_publication(&value).expect_err("cycle"); assert!(issue.message.contains("cycle")); }

    #[test]
    fn accepts_bound_chart_with_nullable_series() {
        let value = bound_chart_publication();
        assert_eq!(validate_publication(&value), Ok(()));
    }

    #[test]
    fn rejects_bound_chart_to_scalar_at_binding_path() {
        let mut value = bound_chart_publication();
        value["stateSchema"]["properties"]["task"]["properties"]["series"] = serde_json::json!({"type":"number"});
        value["initialState"]["task"]["series"] = serde_json::json!(12);
        let issue = validate_publication(&value).expect_err("scalar chart binding");
        assert_eq!(issue.path, "/spec/elements/main/props/values/$state");
    }

    #[test]
    fn rejects_bound_chart_to_undeclared_path_at_binding_path() {
        let mut value = bound_chart_publication();
        value["stateSchema"]["properties"]["task"]["required"] = serde_json::json!([]);
        value["initialState"]["task"] = serde_json::json!({});
        value["stateSchema"]["properties"]["task"]["properties"] = serde_json::json!({});
        let issue = validate_publication(&value).expect_err("undeclared chart binding");
        assert_eq!(issue.path, "/spec/elements/main/props/values/$state");
    }

    fn bound_chart_publication() -> Value {
        let mut value = publication();
        value["spec"]["elements"]["main"] = serde_json::json!({"type":"LineChart","props":{"values":{"$state":"/task/series"}},"children":[]});
        value["stateSchema"]["properties"]["task"]["properties"]["series"] = serde_json::json!({"type":"array","items":{"type":["number","null"]}});
        value["stateSchema"]["properties"]["task"]["required"] = serde_json::json!(["series"]);
        value["initialState"]["task"] = serde_json::json!({"series":[12,null,18]});
        value
    }

#[cfg(test)]
mod conformance_tests {
    //! Anchors this validator to the shared corpus in panel-runtime/fixtures.
    //! It is a third implementation of rules the TypeScript client and server share,
    //! so without a common corpus it drifts and nothing notices.
    use super::validate_publication;
    use std::path::PathBuf;

    /// Fixtures carry the spec half only; publication adds an envelope the agent
    /// supplies at publish time. Wrapping them keeps this about the spec rules the
    /// three implementations must agree on, not about missing envelope fields —
    /// otherwise every adversarial fixture would be rejected for the wrong reason.
    fn load(relative: &str) -> serde_json::Value {
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("cli has a parent directory")
            .join("panel-runtime/fixtures")
            .join(relative);
        let text = std::fs::read_to_string(&path)
            .unwrap_or_else(|error| panic!("cannot read {}: {error}", path.display()));
        let mut value: serde_json::Value = serde_json::from_str(&text)
            .unwrap_or_else(|error| panic!("cannot parse {}: {error}", path.display()));
        // The corpus is not uniform: some fixtures are publication documents and some are
        // bare specs. Nest the bare ones so a rejection is about the spec, not the shape.
        if value.get("root").is_some() && value.get("spec").is_none() {
            value = serde_json::json!({ "spec": value });
        }
        let object = value.as_object_mut().expect("fixture is a JSON object");
        object.entry("protocolVersion").or_insert(serde_json::json!(2));
        object.entry("catalogId").or_insert(serde_json::json!("hiboss.panel"));
        object.entry("catalogVersion").or_insert(serde_json::json!(1));
        object.entry("targetBossId").or_insert(serde_json::json!("boss_conformance"));
        object.entry("taskKey").or_insert(serde_json::json!("conformance"));
        object.entry("sessionId").or_insert(serde_json::json!("session_conformance"));
        object.entry("stateSchema").or_insert(serde_json::json!({
            "type": "object", "properties": {}, "additionalProperties": true
        }));
        object.entry("initialState").or_insert(serde_json::json!({ "task": {} }));
        object.entry("title").or_insert(serde_json::json!("Conformance fixture"));
        value
    }

    #[test]
    fn accepts_every_shipped_example() {
        for name in [
            "metric-panel.json",
            "examples/download-progress.json",
            "examples/e2e-test-run.json",
            "examples/benchmark-sweep.json",
            "examples/service-monitor.json",
            "bound-chart.json",
        ] {
            let value = load(name);
            assert!(
                validate_publication(&value).is_ok(),
                "{name} ships as valid but this validator rejected it: {:?}",
                validate_publication(&value).err()
            );
        }
    }

    #[test]
    fn rejects_every_adversarial_fixture_for_its_own_defect() {
        for name in [
            "cycle.json",
            "over-deep.json",
            "over-large.json",
            "unsafe-pointer.json",
            "unknown-component.json",
            "unknown-action.json",
        ] {
            let error = validate_publication(&load(name))
                .expect_err(&format!("{name} exists to be rejected and this validator accepted it"));
            // The envelope is complete, so a rejection here is about the spec itself.
            assert!(
                error.path.starts_with("/spec") || error.path.starts_with("/formSpec"),
                "{name} was rejected at {} rather than for its own defect",
                error.path
            );
        }
    }

    #[test]
    fn validates_summary_against_the_shared_runtime_fixture() {
        for (name, summary, expected_path) in [
            (
                "missing stage",
                serde_json::json!({"stage": "  ", "headline": {"path": "/task/completed", "label": "Done"}}),
                "/summary/stage",
            ),
            (
                "undeclared headline path",
                serde_json::json!({"stage": "Running", "headline": {"path": "/task/missing", "label": "Missing"}}),
                "/summary/headline/path",
            ),
            (
                "headline object path",
                serde_json::json!({"stage": "Running", "headline": {"path": "/task", "label": "Task"}}),
                "/summary/headline/path",
            ),
            (
                "secondary unit",
                serde_json::json!({"stage": "Running", "secondary": {"path": "/task/label", "label": "Name", "unit": 1}}),
                "/summary/secondary/unit",
            ),
            (
                "non-pointer series",
                serde_json::json!({"stage": "Running", "series": "task/completed"}),
                "/summary/series",
            ),
            (
                "scalar series path",
                serde_json::json!({"stage": "Running", "series": "/task/completed"}),
                "/summary/series/path",
            ),
        ] {
            let mut publication = load("metric-panel.json");
            publication["summary"] = summary;
            let error = validate_publication(&publication)
                .expect_err(&format!("{name} summary must be rejected"));
            assert_eq!(error.path, expected_path, "{name} summary was rejected at the wrong path");
        }

        let mut valid = load("metric-panel.json");
        valid["stateSchema"]["properties"]["task"]["properties"]["trend"] =
            serde_json::json!({"type": "array", "items": {"type": "number"}});
        valid["initialState"]["task"]["trend"] = serde_json::json!([0.1, 0.2]);
        valid["summary"] = serde_json::json!({
            "stage": "Running",
            "metricPath": "/task/completed",
            "headline": {"path": "/task/completed", "label": "Done"},
            "secondary": {"path": "/task/label", "label": "Name", "unit": "text"},
            "series": "/task/trend"
        });
        assert_eq!(validate_publication(&valid), Ok(()));
    }
}
