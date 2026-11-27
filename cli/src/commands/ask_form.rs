// Builds or loads the single catalog v2 input carried in ask metadata.
// Exports FormArgs; uses clap for flag conflicts and shared v2 prop validation.

use super::input_v2;
use clap::Args;
use serde_json::{Value, json};
use std::{error::Error, path::PathBuf};

const ANSWER_POINTER: &str = "/form/answer";
const MAX_FORM_BYTES: usize = 8192;

#[derive(Debug, Args)]
#[group(skip)]
pub(crate) struct FormArgs {
    #[arg(long, value_name = "ID=LABEL[::DESCRIPTION]",
        conflicts_with_all = ["review", "form", "options", "actions",
            "option_images", "option_descriptions", "default_option", "to"],
        help = "Rank 2–20 choices; repeat for each choice")]
    rank: Vec<String>,
    #[arg(
        long,
        requires = "rank",
        value_name = "K",
        help = "Number of ranked choices to return"
    )]
    top: Option<usize>,
    #[arg(long, value_name = "ID=LABEL[::DESCRIPTION]", requires = "verdict",
        conflicts_with_all = ["form", "options", "actions",
            "option_images", "option_descriptions", "default_option", "to"],
        help = "Review 1–50 items; repeat for each item")]
    review: Vec<String>,
    #[arg(
        long,
        value_name = "ID=LABEL[!]",
        requires = "review",
        help = "Review verdict; repeat 2–4 times. A trailing ! requires a note"
    )]
    verdict: Vec<String>,
    #[arg(long, requires = "review", value_parser = ["checklist", "grid"], help = "Review layout")]
    layout: Option<String>,
    #[arg(long, value_name = "FILE.json",
        conflicts_with_all = ["options", "actions", "option_images", "option_descriptions", "default_option", "to"],
        help = "Load a catalog v2 ask form from a JSON file")]
    form: Option<PathBuf>,
}

impl FormArgs {
    pub(crate) fn payload(&self, title: &str) -> Result<Option<Value>, Box<dyn Error>> {
        let form = if let Some(path) = &self.form {
            let bytes = std::fs::read(path)
                .map_err(|error| format!("--form {}: {error}", path.display()))?;
            normalized(serde_json::from_slice(&bytes)
                .map_err(|error| format!("--form {}: {error}", path.display()))?)
        } else {
            let mut props = json!({"label": title, "value": {"$bindState": ANSWER_POINTER}});
            let component = if !self.rank.is_empty() {
                props["options"] = Value::Array(parse_entries(&self.rank, "--rank", false)?);
                if let Some(top) = self.top {
                    props["topK"] = json!(top);
                }
                "RankedChoice"
            } else if !self.review.is_empty() {
                props["items"] = Value::Array(parse_entries(&self.review, "--review", false)?);
                props["verdicts"] = Value::Array(parse_entries(&self.verdict, "--verdict", true)?);
                if let Some(layout) = &self.layout {
                    props["layout"] = json!(layout);
                }
                "ItemReview"
            } else {
                return Ok(None);
            };
            json!({"catalogVersion": 2, "input": {"type": component, "props": props}})
        };
        validate_form(&form)?;
        Ok(Some(form))
    }
}

/// Whole-number floats (`1.0`) become integers, as JavaScript prints them, so the 8 KiB limit
/// counts the same bytes here and on the server.
fn normalized(value: Value) -> Value {
    match value {
        Value::Number(number) => match number.as_f64() {
            Some(float) if number.is_f64() && float.fract() == 0.0 && float.abs() < 9.0e15 => json!(float as i64),
            _ => Value::Number(number),
        },
        Value::Array(items) => Value::Array(items.into_iter().map(normalized).collect()),
        Value::Object(map) => Value::Object(map.into_iter().map(|(key, item)| (key, normalized(item))).collect()),
        other => other,
    }
}

#[cfg(test)]
pub(crate) fn normalized_for_tests(value: Value) -> Value {
    normalized(value)
}

fn parse_entries(values: &[String], flag: &str, verdict: bool) -> Result<Vec<Value>, String> {
    values
        .iter()
        .map(|value| {
            let (id, label) = value
                .split_once('=')
                .ok_or_else(|| format!("{flag} expects ID=LABEL"))?;
            if verdict {
                return Ok(match label.strip_suffix('!') {
                    Some(label) => json!({"id": id, "label": label, "requiresNote": true}),
                    None => json!({"id": id, "label": label}),
                });
            }
            Ok(match label.split_once("::") {
                Some((label, description)) => {
                    json!({"id": id, "label": label, "description": description})
                }
                None => json!({"id": id, "label": label}),
            })
        })
        .collect()
}

fn validate_form(form: &Value) -> Result<(), String> {
    let object = input_v2::fields(form, &["catalogVersion", "input"], &[], "form")?;
    if object["catalogVersion"].as_f64() != Some(2.0) {
        return Err("form.catalogVersion must be 2".into());
    }
    if form.to_string().len() > MAX_FORM_BYTES {
        return Err("form exceeds 8 KiB".into());
    }
    let input = input_v2::fields(&object["input"], &["type", "props"], &[], "form.input")?;
    if input["props"]["value"]["$bindState"].as_str() != Some(ANSWER_POINTER) {
        return Err(format!(
            "form.input.props.value must bind to {ANSWER_POINTER}"
        ));
    }
    input_v2::validate_props(input["type"].as_str().unwrap_or_default(), &input["props"])
        .map_err(|error| format!("form.input.props: {error}"))
}
