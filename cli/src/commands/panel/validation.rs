// Purpose: Validate panel publication JSON without network access.
// Exports: validate_file, validate_publication, ValidationError.
// Dependencies: serde_json and the live panel catalog contract.

#[path = "schema.rs"]
mod schema;
use schema::*;

use serde_json::{Map, Value};
use super::json::parse_unique_json;
use std::error::Error;
use std::fmt::{Display, Formatter};
use std::path::Path;

const CATALOG_ID: &str = "hiboss.panel";
const CATALOG_VERSION: u64 = 1;
const MAX_ELEMENTS: usize = 200;
const MAX_DEPTH: usize = 12;

#[derive(Debug, PartialEq, Eq)]
pub struct ValidationError {
    pub code: &'static str,
    pub path: String,
    pub message: String,
}

impl Display for ValidationError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        let path = if self.path.is_empty() { "/" } else { &self.path };
        write!(f, "{} at {}: {}", self.code, path, self.message)
    }
}

impl Error for ValidationError {}

pub fn validate_file(path: &Path) -> Result<Value, Box<dyn Error>> {
    let body = std::fs::read_to_string(path)?;
    let value = parse_unique_json(&body)
        .map_err(|error| format!("invalid_spec at /: invalid JSON: {error}"))?;
    validate_publication(&value).map_err(|error| Box::new(error) as Box<dyn Error>)?;
    Ok(value)
}

pub fn validate_publication(value: &Value) -> Result<(), ValidationError> {
    let object = object(value, "", "Panel publication")?;
    let allowed = ["protocolVersion", "targetBossId", "taskKey", "sessionId", "title", "catalogId", "catalogVersion", "spec", "stateSchema", "initialState", "summary", "lifecycle", "supersedesPanelId"];
    if let Some(key) = object.keys().find(|key| !allowed.contains(&key.as_str())) {
        return Err(error("invalid_spec", &format!("/{}", escape_pointer(key)), "unknown publication property"));
    }
    require_u64(object, "protocolVersion", "", 2)?;
    if let Some(value) = object.get("lifecycle") { validate_lifecycle(value)?; }
    if object.contains_key("supersedesPanelId") { require_string(object, "supersedesPanelId", "")?; }
    require_string(object, "taskKey", "")?;
    require_string(object, "title", "")?;
    if object.get("catalogId") != Some(&Value::String(CATALOG_ID.to_owned())) {
        return Err(error("unsupported_catalog", "/catalogId", "catalogId must be \"hiboss.panel\""));
    }
    if object.get("catalogVersion").and_then(Value::as_u64) != Some(CATALOG_VERSION) {
        return Err(error("unsupported_catalog", "/catalogVersion", "catalogVersion must be 1"));
    }
    let schema = object_value(object, "stateSchema", "")?;
    if let Some(summary) = object.get("summary") {
        validate_summary(summary, schema)?;
    }
    validate_schema(schema, "/stateSchema")?;
    let initial = object_value(object, "initialState", "")?;
    if !initial.as_object().is_some_and(|state| state.len() == 1 && state.contains_key("task")) {
        return Err(error("invalid_spec", "/initialState", "must contain only the task namespace"));
    }
    validate_value(schema, initial, "/initialState")?;
    let spec = object_value(object, "spec", "")?;
    validate_spec(spec, schema)
}

fn validate_spec(value: &Value, schema: &Value) -> Result<(), ValidationError> {
    let spec = object(value, "/spec", "Panel spec")?;
    let root = non_empty_string(spec, "root", "/spec")?;
    let elements = object_value(spec, "elements", "/spec")?;
    let elements = object(elements, "/spec/elements", "Panel elements")?;
    if elements.len() > MAX_ELEMENTS {
        return Err(error("invalid_spec", "/spec/elements", "panel has too many elements"));
    }
    let paths = schema_paths(schema, "");
    let mut visiting = Vec::new();
    let mut done = Vec::new();
    for (id, element) in elements {
        validate_element(id, element, &paths, schema)?;
    }
    visit_element(root, elements, &mut visiting, &mut done, 1)
}

fn validate_element(id: &str, value: &Value, paths: &[String], state_schema: &Value) -> Result<(), ValidationError> {
    let path = format!("/spec/elements/{}", escape_pointer(id));
    let element = object(value, &path, "Element")?;
    for key in element.keys() {
        if !["type", "props", "children", "on"].contains(&key.as_str()) {
            return Err(error("invalid_spec", &format!("{path}/{key}"), "unknown element property"));
        }
    }
    let component = non_empty_string(element, "type", &path)?;
    if !component_types().contains(&component) {
        return Err(error("invalid_spec", &format!("{path}/type"), &format!("unknown component \"{component}\"")));
    }
    let props = object_value(element, "props", &path)?;
    validate_props(component, props, &format!("{path}/props"), paths, state_schema)?;
    let children = element.get("children").ok_or_else(|| error("invalid_spec", &path, "missing children"))?;
    if !children.as_array().is_some_and(|items| items.iter().all(Value::is_string)) {
        return Err(error("invalid_spec", &format!("{path}/children"), "children must be string element IDs"));
    }
    if let Some(actions) = element.get("on") {
        validate_actions(actions, &format!("{path}/on"))?;
    }
    Ok(())
}

fn validate_props(component: &str, value: &Value, path: &str, paths: &[String], state_schema: &Value) -> Result<(), ValidationError> {
    let props = object(value, path, "Component props")?;
    let (required, allowed) = prop_contract(component);
    for key in required {
        if !props.contains_key(*key) {
            return Err(error("invalid_spec", &format!("{path}/{key}"), "required property is missing"));
        }
    }
    for (key, prop) in props {
        if !allowed.contains(&key.as_str()) {
            return Err(error("invalid_spec", &format!("{path}/{key}"), "unknown component prop"));
        }
        if is_binding(prop) {
            validate_binding(prop, &format!("{path}/{key}"), paths)?;
        }
    }
    validate_prop_values(component, props, path, state_schema)
}

fn validate_prop_values(component: &str, props: &Map<String, Value>, path: &str, state_schema: &Value) -> Result<(), ValidationError> {
    let string_keys = ["label", "unit", "missingText", "placeholder", "description", "message", "variant", "tone", "status"];
    for key in string_keys {
        if props.get(key).is_some_and(|value| !value.is_string()) {
            return Err(error("invalid_spec", &format!("{path}/{key}"), "must be a string"));
        }
    }
    if component == "Stack" && !matches!(props.get("direction").and_then(Value::as_str), Some("vertical" | "horizontal")) {
        return Err(error("invalid_spec", &format!("{path}/direction"), "must be vertical or horizontal"));
    }
    if component == "Text" && !props.get("text").is_some_and(|value| value.is_string() || is_binding(value)) {
        return Err(error("invalid_spec", &format!("{path}/text"), "must be a string or supported binding"));
    }
    if component == "Grid" && !props.get("columns").is_some_and(|value| value.as_u64().is_some_and(|n| n > 0)) {
        return Err(error("invalid_spec", &format!("{path}/columns"), "must be a positive integer"));
    }
    if ["LineChart", "BarChart"].contains(&component) {
        validate_chart_values(props.get("values"), &format!("{path}/values"), state_schema)?;
    }
    if ["Select", "MultiSelect"].contains(&component) && !valid_options(props.get("options")) {
        return Err(error("invalid_spec", &format!("{path}/options"), "must contain non-empty id and label strings"));
    }
    Ok(())
}

fn validate_chart_values(value: Option<&Value>, path: &str, state_schema: &Value) -> Result<(), ValidationError> {
    if value.is_some_and(valid_chart_literal) { return Ok(()); }
    let binding = value.and_then(Value::as_object).ok_or_else(|| error("invalid_spec", path, "must be finite numbers, nulls, or a $state binding"))?;
    if binding.len() != 1 || !binding.contains_key("$state") { return Err(error("invalid_spec", path, "must use a $state binding")); }
    let pointer = binding.get("$state").and_then(Value::as_str).ok_or_else(|| error("invalid_spec", &format!("{path}/$state"), "must be a JSON Pointer"))?;
    let decoded = decode_pointer(pointer).map_err(|message| error("invalid_spec", &format!("{path}/$state"), message))?;
    let schema = schema_at_pointer(state_schema, &decoded);
    if !valid_chart_schema(schema) { return Err(error("invalid_spec", &format!("{path}/$state"), "must point to an array of numbers or nulls")); }
    Ok(())
}

fn validate_binding(value: &Value, path: &str, paths: &[String]) -> Result<(), ValidationError> {
    let object = value.as_object().ok_or_else(|| error("invalid_spec", path, "binding must be an object"))?;
    if object.len() != 1 || !object.keys().next().is_some_and(|key| ["$state", "$bindState", "$item", "$index", "$bindItem"].contains(&key.as_str())) {
        return Err(error("invalid_spec", path, "binding must use one supported expression"));
    }
    let (key, pointer) = object.iter().next().ok_or_else(|| error("invalid_spec", path, "binding is empty"))?;
    if key == "$index" {
        if !pointer.as_u64().is_some_and(|index| index <= u64::MAX) {
            return Err(error("invalid_spec", &format!("{path}/$index"), "must be a non-negative integer"));
        }
        return Ok(());
    }
    let pointer = pointer.as_str().ok_or_else(|| error("invalid_spec", &format!("{path}/{key}"), "must be a JSON Pointer"))?;
    let decoded = decode_pointer(pointer).map_err(|message| error("invalid_spec", &format!("{path}/{key}"), message))?;
    if !paths.iter().any(|declared| declared == pointer) {
        return Err(error("invalid_spec", &format!("{path}/{key}"), "binding path is not declared"));
    }
    if decoded.is_empty() { return Err(error("invalid_spec", &format!("{path}/{key}"), "binding path must not be empty")); }
    Ok(())
}

fn validate_actions(value: &Value, path: &str) -> Result<(), ValidationError> {
    let actions = object(value, path, "Element actions")?;
    for (event, value) in actions {
        let action = object(value, &format!("{path}/{event}"), "Action")?;
        if let Some(key) = action.keys().find(|key| !["action", "params"].contains(&key.as_str())) {
            return Err(error("invalid_spec", &format!("{path}/{event}/{key}"), "unknown action property"));
        }
        let action_name = non_empty_string(action, "action", &format!("{path}/{event}"))?;
        if !["submitRequest", "openPanel"].contains(&action_name) {
            return Err(error("invalid_spec", &format!("{path}/{event}/action"), &format!("unknown action \"{action_name}\"")));
        }
        if let Some(params) = action.get("params") {
            let params = params.as_object().ok_or_else(|| error("invalid_spec", &format!("{path}/{event}/params"), "action params must be an object"))?;
            if action_name == "submitRequest" && !params.is_empty() {
                return Err(error("invalid_spec", &format!("{path}/{event}/params"), "submitRequest does not accept params"));
            }
            if action_name == "openPanel" {
                if params.keys().any(|key| key != "panelId") { return Err(error("invalid_spec", &format!("{path}/{event}/params"), "openPanel only accepts panelId")); }
                if !params.get("panelId").is_some_and(Value::is_string) { return Err(error("invalid_spec", &format!("{path}/{event}/params/panelId"), "must be a string")); }
            }
        } else if action_name == "openPanel" {
            return Err(error("invalid_spec", &format!("{path}/{event}/params/panelId"), "openPanel requires panelId"));
        }
    }
    Ok(())
}

fn visit_element(id: &str, elements: &Map<String, Value>, visiting: &mut Vec<String>, done: &mut Vec<String>, depth: usize) -> Result<(), ValidationError> {
    let path = format!("/spec/elements/{}/children", escape_pointer(id));
    if depth > MAX_DEPTH { return Err(error("invalid_spec", &path, "tree depth exceeds 12")); }
    if visiting.iter().any(|current| current == id) { return Err(error("invalid_spec", &path, "panel tree contains a cycle")); }
    if done.iter().any(|current| current == id) { return Ok(()); }
    let element = elements.get(id).ok_or_else(|| error("invalid_spec", &path, &format!("unknown child element \"{id}\"")))?;
    visiting.push(id.to_owned());
    if let Some(children) = element.get("children").and_then(Value::as_array) {
        for (index, child) in children.iter().enumerate() {
            let child = child.as_str().unwrap_or_default();
            visit_element(child, elements, visiting, done, depth + 1).map_err(|mut issue| {
                if issue.path == path { issue.path = format!("{path}/{index}"); }
                issue
            })?;
        }
    }
    visiting.pop();
    done.push(id.to_owned());
    Ok(())
}

fn object<'a>(value: &'a Value, path: &str, name: &str) -> Result<&'a Map<String, Value>, ValidationError> { value.as_object().ok_or_else(|| error("invalid_spec", path, &format!("{name} must be an object"))) }
fn object_value<'a>(object: &'a Map<String, Value>, key: &str, path: &str) -> Result<&'a Value, ValidationError> { object.get(key).ok_or_else(|| error("invalid_spec", &format!("{path}/{key}"), "required property is missing")) }
fn require_string(object: &Map<String, Value>, key: &str, path: &str) -> Result<(), ValidationError> { let value = object_value(object, key, path)?; if !value.is_string() || value.as_str().is_some_and(str::is_empty) { return Err(error("invalid_spec", &format!("{path}/{key}"), "must be a non-empty string")); } Ok(()) }
fn non_empty_string<'a>(object: &'a Map<String, Value>, key: &str, path: &str) -> Result<&'a str, ValidationError> { let value = object_value(object, key, path)?; value.as_str().filter(|value| !value.is_empty()).ok_or_else(|| error("invalid_spec", &format!("{path}/{key}"), "must be a non-empty string")) }
fn require_u64(object: &Map<String, Value>, key: &str, path: &str, expected: u64) -> Result<(), ValidationError> { let value = object_value(object, key, path)?; if value.as_u64() != Some(expected) { return Err(error("invalid_spec", &format!("{path}/{key}"), &format!("must be {expected}"))); } Ok(()) }
fn error(code: &'static str, path: &str, message: &str) -> ValidationError { ValidationError { code, path: path.to_owned(), message: message.to_owned() } }
fn escape_pointer(value: &str) -> String { value.replace('~', "~0").replace('/', "~1") }
fn decode_pointer(value: &str) -> Result<Vec<String>, &'static str> { if !value.starts_with('/') { return Err("binding must be a JSON Pointer"); } let mut result = Vec::new(); for segment in value[1..].split('/') { let mut decoded = String::new(); let mut chars = segment.chars(); while let Some(character) = chars.next() { if character != '~' { decoded.push(character); continue; } match chars.next() { Some('0') => decoded.push('~'), Some('1') => decoded.push('/'), _ => return Err("binding contains an invalid JSON Pointer escape") } } if ["__proto__", "prototype", "constructor"].contains(&decoded.as_str()) { return Err("binding contains a dangerous JSON Pointer segment"); } result.push(decoded); } Ok(result) }
fn is_binding(value: &Value) -> bool { value.as_object().is_some_and(|object| object.keys().any(|key| key.starts_with('$'))) }
fn component_types() -> Vec<&'static str> { vec!["Stack", "Grid", "Section", "Text", "Metric", "Progress", "Status", "Table", "LineChart", "BarChart", "TextInput", "TextArea", "NumberInput", "Select", "MultiSelect", "Toggle", "Slider", "Button"] }
fn prop_contract(component: &str) -> (&'static [&'static str], &'static [&'static str]) { match component { "Stack" => (&["direction"], &["direction", "gap"]), "Grid" => (&["columns"], &["columns", "gap"]), "Section" => (&["label"], &["label", "description", "collapsible"]), "Text" => (&["text"], &["text", "tone"]), "Metric" => (&["label", "value"], &["label", "value", "unit", "missingText"]), "Progress" => (&["label", "value"], &["label", "value", "min", "max"]), "Status" => (&["label", "status"], &["label", "status", "message"]), "Table" => (&["label", "columns"], &["label", "columns", "rows", "rowsBinding"]), "LineChart" | "BarChart" => (&["values"], &["label", "values", "unit"]), "TextInput" | "TextArea" => (&["label", "value"], &["label", "value", "placeholder", "minLength", "maxLength", "rows"]), "NumberInput" => (&["label", "value"], &["label", "value", "min", "max", "step"]), "Select" => (&["label", "value", "options"], &["label", "value", "options", "placeholder"]), "MultiSelect" => (&["label", "value", "options"], &["label", "value", "options"]), "Toggle" => (&["label", "value"], &["label", "value", "description"]), "Slider" => (&["label", "value", "min", "max"], &["label", "value", "min", "max", "step"]), "Button" => (&["label"], &["label", "variant", "disabled"]), _ => (&[], &[]), } }
fn valid_chart_literal(value: &Value) -> bool { value.as_array().is_some_and(|items| items.iter().all(|item| item.is_null() || item.as_f64().is_some_and(f64::is_finite))) }
fn valid_chart_schema(value: Option<&Value>) -> bool {
    let Some(schema) = value.and_then(Value::as_object) else { return false; };
    let Some(types) = schema.get("type").and_then(schema_type_list) else { return false; };
    if types != ["array"] { return false; }
    let Some(items) = schema.get("items").and_then(Value::as_object) else { return false; };
    let Some(item_types) = items.get("type").and_then(schema_type_list) else { return false; };
    item_types == ["number"] || (item_types.len() == 2 && item_types.contains(&"number") && item_types.contains(&"null"))
}
fn valid_options(value: Option<&Value>) -> bool { value.and_then(Value::as_array).is_some_and(|items| !items.is_empty() && items.iter().all(|item| item.get("id").and_then(Value::as_str).is_some_and(|value| !value.is_empty()) && item.get("label").and_then(Value::as_str).is_some_and(|value| !value.is_empty()))) }

#[cfg(test)]
#[path = "validation_tests.rs"]
mod tests;

fn validate_lifecycle(value: &Value) -> Result<(), ValidationError> {
    let policy = object(value, "/lifecycle", "Lifecycle")?;
    if policy.keys().any(|key| !["mode", "expectedUpdateIntervalSeconds"].contains(&key.as_str())) {
        return Err(error("invalid_spec", "/lifecycle", "unsupported lifecycle property"));
    }
    if policy.get("mode").is_some_and(|value| ![Some("run"), Some("monitor")].contains(&value.as_str())) {
        return Err(error("invalid_spec", "/lifecycle/mode", "must be run or monitor"));
    }
    if policy.get("expectedUpdateIntervalSeconds").is_some_and(|value| !value.as_u64().is_some_and(|value| (5..=3600).contains(&value))) {
        return Err(error("invalid_spec", "/lifecycle/expectedUpdateIntervalSeconds", "must be an integer from 5 to 3600"));
    }
    Ok(())
}
