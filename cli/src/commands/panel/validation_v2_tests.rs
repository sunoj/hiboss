// Verifies catalog v2 publication support and version gating.
// Dependencies: the parent validation tests and serde_json.
use super::*;

#[test]
fn catalog_v2_accepts_v1_components_and_rejects_unsupported_versions() {
    let mut value = publication();
    value["catalogVersion"] = Value::from(2);
    assert_eq!(validate_publication(&value), Ok(()));
    value["catalogVersion"] = Value::from(3);
    let issue = validate_publication(&value).expect_err("unsupported version");
    assert_eq!(issue.code, "unsupported_catalog");
    assert_eq!(issue.path, "/catalogVersion");
}

#[test]
fn ranking_and_review_components_require_catalog_v2() {
    use serde_json::json;

    let entries = json!([{"id": "a", "label": "A"}, {"id": "b", "label": "B"}]);
    for (component, mut props) in [
        ("RankedChoice", json!({"options": entries, "topK": 1})),
        ("ItemReview", json!({"items": entries, "verdicts": entries, "layout": "grid"})),
    ] {
        let mut value = publication();
        props["label"] = json!("Question");
        props["value"] = json!({"$bindState": "/task/done"});
        value["spec"]["elements"]["input"] = json!({"type": component, "props": props, "children": []});
        value["spec"]["elements"]["main"]["children"] = json!(["input"]);
        let issue = validate_publication(&value).expect_err("v2 input on v1");
        assert_eq!(issue.path, "/spec/elements/input/type");
        assert_eq!(issue.message, format!("\"{component}\" needs catalogVersion 2"));
        value["catalogVersion"] = json!(2);
        assert_eq!(validate_publication(&value), Ok(()));
    }
}
