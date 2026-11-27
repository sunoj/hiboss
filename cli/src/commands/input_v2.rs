// Validates catalog v2 input props for ask forms and panel publications.
// Exports shared input names and validation against the panel-runtime prop contract.

use serde_json::{Map, Value};
use std::collections::HashSet;

pub(super) const TYPES: [&str; 2] = ["RankedChoice", "ItemReview"];

pub(super) fn validate_props(component: &str, props: &Value) -> Result<(), String> {
    let required = match component {
        "RankedChoice" => ["label", "value", "options"].as_slice(),
        "ItemReview" => ["label", "value", "items", "verdicts"].as_slice(),
        _ => return Err(format!("input type must be one of {}", TYPES.join(", "))),
    };
    let optional = if component == "RankedChoice" {
        "topK"
    } else {
        "layout"
    };
    let props = fields(props, required, &[optional], "props")?;
    validate_string(&props["label"], 1, usize::MAX, "label")?;
    let binding = fields(&props["value"], &["$bindState"], &[], "value")?;
    if !binding["$bindState"]
        .as_str()
        .is_some_and(|path| path.starts_with('/'))
    {
        return Err("value.$bindState must be a JSON Pointer".into());
    }
    if component == "RankedChoice" {
        let count = entries(&props["options"], "options", 2, 20)?;
        if let Some(top) = props.get("topK") {
            if !top
                .as_f64()
                .is_some_and(|n| n.fract() == 0.0 && (1.0..=count as f64).contains(&n))
            {
                return Err(format!("topK must be an integer from 1 to {count}"));
            }
        }
    } else {
        entries(&props["items"], "items", 1, 50)?;
        entries(&props["verdicts"], "verdicts", 2, 4)?;
        if let Some(layout) = props.get("layout") {
            if !matches!(layout.as_str(), Some("checklist" | "grid")) {
                return Err("layout must be checklist or grid".into());
            }
        }
    }
    Ok(())
}

pub(super) fn fields<'a>(
    value: &'a Value,
    required: &[&str],
    optional: &[&str],
    name: &str,
) -> Result<&'a Map<String, Value>, String> {
    let object = value
        .as_object()
        .ok_or_else(|| format!("{name} must be an object"))?;
    if let Some(key) = required.iter().find(|key| !object.contains_key(**key)) {
        return Err(format!("{name}.{key} is required"));
    }
    if let Some(key) = object
        .keys()
        .find(|key| !required.contains(&key.as_str()) && !optional.contains(&key.as_str()))
    {
        return Err(format!("unknown property {name}.{key}"));
    }
    Ok(object)
}

fn entries(value: &Value, name: &str, min: usize, max: usize) -> Result<usize, String> {
    let list = value
        .as_array()
        .filter(|list| (min..=max).contains(&list.len()))
        .ok_or_else(|| format!("{name} must contain {min}–{max} entries"))?;
    let verdict = name == "verdicts";
    let optional = if verdict {
        "requiresNote"
    } else {
        "description"
    };
    let mut ids = HashSet::new();
    for (index, entry) in list.iter().enumerate() {
        let path = format!("{name}[{index}]");
        let entry = fields(entry, &["id", "label"], &[optional], &path)?;
        let id = validate_string(&entry["id"], 1, 64, &format!("{path}.id"))?;
        if !ids.insert(id) {
            return Err(format!("{name} ids must be unique (duplicate {id:?})"));
        }
        let label_max = if verdict { 60 } else { 200 };
        validate_string(&entry["label"], 1, label_max, &format!("{path}.label"))?;
        if let Some(extra) = entry.get(optional) {
            if verdict {
                if !extra.is_boolean() {
                    return Err(format!("{path}.requiresNote must be a boolean"));
                }
            } else {
                validate_string(extra, 0, 400, &format!("{path}.description"))?;
            }
        }
    }
    Ok(list.len())
}

fn validate_string<'a>(
    value: &'a Value,
    min: usize,
    max: usize,
    name: &str,
) -> Result<&'a str, String> {
    // JavaScript string lengths count UTF-16 code units.
    value
        .as_str()
        .filter(|text| (min..=max).contains(&text.encode_utf16().count()))
        .ok_or_else(|| format!("{name} must be a string of {min}–{max} UTF-16 code units"))
}
