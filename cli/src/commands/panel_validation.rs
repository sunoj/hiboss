// Purpose: Validate panel publication JSON without network access.
// Exports: validate_file, validate_publication, ValidationError.
// Dependencies: serde_json and the live panel catalog contract.

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
    let allowed = ["protocolVersion", "targetBossId", "taskKey", "sessionId", "title", "catalogId", "catalogVersion", "spec", "stateSchema", "initialState", "summary"];
    if let Some(key) = object.keys().find(|key| !allowed.contains(&key.as_str())) {
        return Err(error("invalid_spec", &format!("/{}", escape_pointer(key)), "unknown publication property"));
    }
    require_u64(object, "protocolVersion", "", 1)?;
    require_string(object, "targetBossId", "")?;
    require_string(object, "taskKey", "")?;
    require_string(object, "sessionId", "")?;
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
    validate_value(schema, initial, "/initialState")?;
    let spec = object_value(object, "spec", "")?;
    validate_spec(spec, schema)
}

fn validate_summary(value: &Value, schema: &Value) -> Result<(), ValidationError> {
    let summary = object(value, "/summary", "Summary")?;
    if !summary.get("stage").and_then(Value::as_str).is_some_and(|stage| !stage.trim().is_empty()) {
        return Err(error("invalid_spec", "/summary/stage", "Summary stage must be a non-empty string"));
    }
    if let Some(headline) = summary.get("headline") {
        validate_summary_value(headline, "/summary/headline", schema, false)?;
    }
    if let Some(secondary) = summary.get("secondary") {
        validate_summary_value(secondary, "/summary/secondary", schema, false)?;
    }
    if let Some(series) = summary.get("series") {
        let pointer = series.as_str().filter(|value| value.starts_with('/')).ok_or_else(|| {
            error("invalid_spec", "/summary/series", "Summary series must be a JSON Pointer")
        })?;
        validate_summary_path(pointer, schema, "/summary/series", true)?;
    }
    Ok(())
}

fn validate_summary_value(value: &Value, path: &str, schema: &Value, require_array: bool) -> Result<(), ValidationError> {
    let Some(object) = value.as_object() else {
        return Err(error("invalid_spec", path, "Summary value must have a JSON Pointer path and label"));
    };
    if !object.get("path").and_then(Value::as_str).is_some_and(|value| value.starts_with('/'))
        || !object.get("label").and_then(Value::as_str).is_some_and(|value| !value.trim().is_empty())
    {
        return Err(error("invalid_spec", path, "Summary value must have a JSON Pointer path and label"));
    }
    if object.get("unit").is_some_and(|value| !value.is_string()) {
        return Err(error("invalid_spec", &format!("{path}/unit"), "Summary unit must be a string"));
    }
    let Some(pointer) = object.get("path").and_then(Value::as_str) else {
        return Err(error("invalid_spec", path, "Summary value must have a JSON Pointer path and label"));
    };
    validate_summary_path(pointer, schema, path, require_array)
}

fn validate_summary_path(pointer: &str, schema: &Value, summary_path: &str, require_array: bool) -> Result<(), ValidationError> {
    let Some(node) = schema_node_at_path(schema, pointer) else {
        return Err(error("invalid_spec", &format!("{summary_path}/path"), "Summary path is not declared in stateSchema"));
    };
    if !schema_paths(schema, "").iter().any(|path| path == pointer) {
        return Err(error("invalid_spec", &format!("{summary_path}/path"), "Summary path is not declared in stateSchema"));
    }
    let is_array = node.get("type").and_then(Value::as_str) == Some("array");
    let is_object = node.get("type").and_then(Value::as_str) == Some("object") || node.get("properties").is_some();
    if (require_array && !is_array) || (!require_array && (is_array || is_object)) {
        let message = if require_array { "Summary series path must resolve to an array" } else { "Summary value path must resolve to a scalar" };
        return Err(error("invalid_spec", &format!("{summary_path}/path"), message));
    }
    Ok(())
}

fn schema_node_at_path<'a>(schema: &'a Value, pointer: &str) -> Option<&'a Value> {
    let mut current = schema;
    for segment in pointer[1..].split('/').map(|segment| segment.replace("~1", "/").replace("~0", "~")) {
        current = current.get("properties")?.as_object()?.get(&segment)?;
    }
    current.is_object().then_some(current)
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

fn validate_schema(value: &Value, path: &str) -> Result<(), ValidationError> {
    let schema = object(value, path, "State schema")?;
    let allowed = ["type", "properties", "required", "additionalProperties", "items", "enum", "minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems", "uniqueItems"];
    if let Some(key) = schema.keys().find(|key| !allowed.contains(&key.as_str())) {
        return Err(error("invalid_spec", &format!("{path}/{key}"), "unsupported schema keyword"));
    }
    let schema_types = schema_types(schema, path)?;
    if schema_types.iter().any(|schema_type| *schema_type == "object") {
        if let Some(properties) = schema.get("properties") { let properties = object(properties, &format!("{path}/properties"), "Schema properties")?; for (key, child) in properties { validate_schema(child, &format!("{path}/properties/{}", escape_pointer(key)))?; } }
        if let Some(required) = schema.get("required") { if !required.as_array().is_some_and(|items| items.iter().all(Value::is_string)) { return Err(error("invalid_spec", &format!("{path}/required"), "must be an array of strings")); } }
        if schema.get("additionalProperties").is_some_and(|value| !value.is_boolean()) { return Err(error("invalid_spec", &format!("{path}/additionalProperties"), "must be a boolean")); }
    }
    if let Some(items) = schema.get("items") { validate_schema(items, &format!("{path}/items"))?; }
    if let Some(enum_values) = schema.get("enum") { if !enum_values.is_array() { return Err(error("invalid_spec", &format!("{path}/enum"), "must be an array")); } }
    Ok(())
}

fn validate_value(schema: &Value, value: &Value, path: &str) -> Result<(), ValidationError> {
    let schema = schema.as_object().ok_or_else(|| error("invalid_spec", path, "state schema must be an object"))?;
    let schema_types = schema_types(schema, path)?;
    if !schema_types.iter().any(|schema_type| value_matches_type(schema_type, value)) { return Err(error("invalid_spec", path, &format!("initial state does not match schema type {}", schema_types.join(" or ")))); }
    if schema_types.iter().any(|schema_type| ["number", "integer"].contains(schema_type)) { if let Some(minimum) = schema.get("minimum").and_then(Value::as_f64) { if value.as_f64().is_some_and(|number| number < minimum) { return Err(error("invalid_spec", path, "initial state is below minimum")); } } if let Some(maximum) = schema.get("maximum").and_then(Value::as_f64) { if value.as_f64().is_some_and(|number| number > maximum) { return Err(error("invalid_spec", path, "initial state is above maximum")); } } }
    if schema_types.contains(&"string") { if let Some(minimum) = schema.get("minLength").and_then(Value::as_u64) { if value.as_str().is_some_and(|text| text.chars().count() < minimum as usize) { return Err(error("invalid_spec", path, "initial state string is too short")); } } if let Some(maximum) = schema.get("maxLength").and_then(Value::as_u64) { if value.as_str().is_some_and(|text| text.chars().count() > maximum as usize) { return Err(error("invalid_spec", path, "initial state string is too long")); } } }
    if schema_types.contains(&"array") { if let Some(minimum) = schema.get("minItems").and_then(Value::as_u64) { if value.as_array().is_some_and(|items| items.len() < minimum as usize) { return Err(error("invalid_spec", path, "initial state array is too short")); } } if let Some(maximum) = schema.get("maxItems").and_then(Value::as_u64) { if value.as_array().is_some_and(|items| items.len() > maximum as usize) { return Err(error("invalid_spec", path, "initial state array is too long")); } } }
    if let Some(enum_values) = schema.get("enum").and_then(Value::as_array) { if !enum_values.contains(value) { return Err(error("invalid_spec", path, "initial state is not an allowed value")); } }
    if schema_types.contains(&"object") { validate_object_value(schema, value, path)?; }
    if schema_types.contains(&"array") { if let Some(items) = schema.get("items") { for (index, child) in value.as_array().into_iter().flatten().enumerate() { validate_value(items, child, &format!("{path}/{index}"))?; } } }
    Ok(())
}

fn validate_object_value(schema: &Map<String, Value>, value: &Value, path: &str) -> Result<(), ValidationError> {
    let object = value.as_object().ok_or_else(|| error("invalid_spec", path, "initial state must be an object"))?;
    if let Some(required) = schema.get("required").and_then(Value::as_array) { for key in required.iter().filter_map(Value::as_str) { if !object.contains_key(key) { return Err(error("invalid_spec", &format!("{path}/{key}"), "required state value is missing")); } } }
    if schema.get("additionalProperties") == Some(&Value::Bool(false)) { if let Some(properties) = schema.get("properties").and_then(Value::as_object) { if let Some(key) = object.keys().find(|key| !properties.contains_key(*key)) { return Err(error("invalid_spec", &format!("{path}/{}", escape_pointer(key)), "unknown state property")); } } }
    if let Some(properties) = schema.get("properties").and_then(Value::as_object) { for (key, child_schema) in properties { if let Some(child) = object.get(key) { validate_value(child_schema, child, &format!("{path}/{}", escape_pointer(key)))?; } } }
    Ok(())
}

fn schema_paths(value: &Value, path: &str) -> Vec<String> {
    let Some(properties) = value.get("properties").and_then(Value::as_object) else { return if path.is_empty() { Vec::new() } else { vec![path.to_owned()] }; };
    let mut paths = Vec::new();
    for (key, child) in properties { let child_path = format!("{path}/{}", escape_pointer(key)); paths.push(child_path.clone()); paths.extend(schema_paths(child, &child_path)); }
    paths
}

fn schema_types<'a>(schema: &'a Map<String, Value>, path: &str) -> Result<Vec<&'a str>, ValidationError> {
    let value = object_value(schema, "type", path)?;
    let types = schema_type_list(value).unwrap_or_default();
    if types.is_empty() || types.iter().any(|schema_type| !["object", "array", "string", "number", "integer", "boolean", "null"].contains(schema_type)) {
        return Err(error("invalid_spec", &format!("{path}/type"), "unsupported schema type"));
    }
    Ok(types)
}

fn schema_type_list(value: &Value) -> Option<Vec<&str>> {
    match value {
        Value::String(schema_type) => Some(vec![schema_type.as_str()]),
        Value::Array(types) if !types.is_empty() && types.iter().all(Value::is_string) => Some(types.iter().filter_map(Value::as_str).collect()),
        _ => None,
    }
}

fn value_matches_type(schema_type: &str, value: &Value) -> bool {
    match schema_type {
        "object" => value.is_object(), "array" => value.is_array(), "string" => value.is_string(),
        "number" => value.as_f64().is_some(), "integer" => value.as_i64().is_some() || value.as_u64().is_some(),
        "boolean" => value.is_boolean(), "null" => value.is_null(), _ => false,
    }
}

fn schema_at_pointer<'a>(schema: &'a Value, path: &[String]) -> Option<&'a Value> {
    let mut current = schema;
    for segment in path {
        current = current.get("properties")?.get(segment)?;
    }
    Some(current)
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
mod tests {
    use super::*;

    fn publication() -> Value {
        serde_json::json!({"protocolVersion":1,"targetBossId":"boss_1","taskKey":"task_1","sessionId":"session_1","title":"Panel","catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Metric","props":{"label":"Done","value":{"$state":"/task/done"}},"children":[]}}},"stateSchema":{"type":"object","properties":{"task":{"type":"object","properties":{"done":{"type":"integer"}},"required":["done"],"additionalProperties":false}},"required":["task"],"additionalProperties":false},"initialState":{"task":{"done":0}}})
    }

    #[test]
    fn accepts_valid_publication() { assert_eq!(validate_publication(&publication()), Ok(())); }

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
        object.entry("protocolVersion").or_insert(serde_json::json!(1));
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
