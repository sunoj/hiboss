// Exercises catalog v2 form asks through clap and the ask request builder.
// Dependencies: the parent ask module and serde_json fixtures.

use super::*;
use clap::Parser;
use serde_json::json;

#[derive(Debug, Parser)]
struct Command {
    #[command(flatten)]
    args: AskArgs,
}

#[tokio::test]
async fn ranked_ask_sends_a_blocking_form() {
    let args = Command::parse_from([
        "ask",
        "Rank fixes",
        "--rank",
        "sync=Fix sync::Flaky on CI",
        "--rank",
        "docs=Update docs",
        "--top",
        "1",
    ])
    .args;
    let client = HiBossClient::new("http://127.0.0.1:1", "test-key");
    let request = prepare_request(
        &args,
        &client,
        &args.choice_payload().unwrap(),
        &Tools::system(),
    )
    .await
    .unwrap();
    assert_eq!(request.mode, "blocking");
    assert!(request.options.is_none());
    assert_eq!(
        request.metadata.unwrap()["form"],
        json!({
            "catalogVersion": 2,
            "input": {"type": "RankedChoice", "props": {
                "label": "Rank fixes", "value": {"$bindState": "/form/answer"}, "topK": 1,
                "options": [
                    {"id": "sync", "label": "Fix sync", "description": "Flaky on CI"},
                    {"id": "docs", "label": "Update docs"}
                ]
            }}
        })
    );
}

#[test]
fn review_ask_builds_items_and_note_required_verdicts() {
    let args = Command::parse_from([
        "ask",
        "--review",
        "s=Sync::Check logs",
        "--verdict",
        "yes=Confirmed",
        "--verdict",
        "no=Cannot confirm!",
        "--layout",
        "grid",
        "Review checks",
    ])
    .args;
    assert_eq!(
        args.form.payload(&args.body).unwrap().unwrap(),
        json!({
            "catalogVersion": 2,
            "input": {"type": "ItemReview", "props": {
                "label": "Review checks", "value": {"$bindState": "/form/answer"}, "layout": "grid",
                "items": [{"id": "s", "label": "Sync", "description": "Check logs"}],
                "verdicts": [{"id": "yes", "label": "Confirmed"},
                             {"id": "no", "label": "Cannot confirm", "requiresNote": true}]
            }}
        })
    );
}

#[test]
fn form_flags_conflict_with_all_choice_flags_and_each_other() {
    let rank = ["--rank", "a=A", "--rank", "b=B"];
    let review = ["--review", "a=A", "--verdict", "y=Yes", "--verdict", "n=No"];
    let file = ["--form", "form.json"];
    let modes: [&[&str]; 3] = [&rank, &review, &file];
    let flags = [
        ["--option", "A"],
        ["--action", "A=run"],
        ["--option-image", "A=x.png"],
        ["--option-description", "A=text"],
        ["--default", "A"],
    ];
    for (index, mode) in modes.iter().enumerate() {
        for other in modes[index + 1..]
            .iter()
            .copied()
            .chain(flags.iter().map(|flag| flag.as_slice()))
        {
            let args = ["ask", "Title"]
                .into_iter()
                .chain(mode.iter().copied())
                .chain(other.iter().copied());
            let error = Command::try_parse_from(args).expect_err("flags conflict");
            assert_eq!(
                error.kind(),
                clap::error::ErrorKind::ArgumentConflict,
                "{error}"
            );
        }
    }
}

#[test]
fn form_flags_validate_counts_ids_and_companion_arguments() {
    for (flags, message) in [
        (&["--rank", "a=A"][..], "2–20"),
        (&["--rank", "a=A", "--rank", "a=B"], "duplicate"),
        (&["--rank", "a=A", "--rank", "=B"], ".id"),
        (&["--rank", "a=A", "--rank", "b=B", "--top", "3"], "topK"),
        (&["--review", "a=A", "--verdict", "y=Yes"], "2–4"),
        (
            &["--review", "a=A", "--verdict", "y=Yes", "--verdict", "y=No"],
            "duplicate",
        ),
    ] {
        let args =
            Command::parse_from(["ask", "Title"].into_iter().chain(flags.iter().copied())).args;
        let error = args.form.payload(&args.body).unwrap_err().to_string();
        assert!(error.contains(message), "{error}");
    }
    for flags in [
        &["--top", "2"][..],
        &["--layout", "grid"],
        &["--review", "a=A"],
        &["--verdict", "a=A"],
    ] {
        assert!(
            Command::try_parse_from(["ask", "Title"].into_iter().chain(flags.iter().copied()))
                .is_err()
        );
    }
}

#[test]
fn form_file_preserves_props_and_rejects_duplicate_ids() {
    let path =
        std::env::temp_dir().join(format!("hiboss-ask-form-test-{}.json", std::process::id()));
    let mut form = json!({
        "catalogVersion": 2,
        "input": {"type": "RankedChoice", "props": {
            "label": "Label from file", "value": {"$bindState": "/form/answer"},
            "options": [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}]
        }}
    });
    let args =
        Command::parse_from(["ask", "Different title", "--form", path.to_str().unwrap()]).args;
    std::fs::write(&path, form.to_string()).unwrap();
    let loaded = args.form.payload(&args.body);
    form["input"]["props"]["options"][1]["id"] = json!("a");
    std::fs::write(&path, form.to_string()).unwrap();
    let duplicate = args.form.payload(&args.body);
    std::fs::remove_file(&path).unwrap();
    assert_eq!(
        loaded.unwrap().unwrap()["input"]["props"]["label"],
        "Label from file"
    );
    assert!(duplicate.unwrap_err().to_string().contains("duplicate"));
}

#[test]
fn a_form_ask_cannot_go_to_another_agent() {
    let error = Command::try_parse_from(["ask", "Rank", "--rank", "a=A", "--rank", "b=B", "--to", "peer"])
        .expect_err("--to conflicts with a form");
    assert_eq!(error.kind(), clap::error::ErrorKind::ArgumentConflict);
}

#[test]
fn ids_are_ascii_only() {
    let props = json!({"label": "Rank", "value": {"$bindState": "/form/answer"},
        "options": [{"id": "\u{e9}", "label": "One"}, {"id": "b", "label": "Two"}]});
    assert!(super::input_v2::validate_props("RankedChoice", &props).is_err());
}

#[test]
fn whole_number_floats_count_as_javascript_prints_them() {
    let form = super::ask_form::normalized_for_tests(json!({"topK": 1.0, "nested": [2.0, 2.5]}));
    assert_eq!(form.to_string(), r#"{"nested":[2,2.5],"topK":1}"#);
}
