// Validates declared task schemas and initial values.
// Exports schema checks to the panel publication validator.
// Dependencies: parent JSON helpers and ValidationError.
use super::*;

pub(super) fn validate_schema(value: &Value, path: &str) -> Result<(), ValidationError> {
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

pub(super) fn validate_value(schema: &Value, value: &Value, path: &str) -> Result<(), ValidationError> {
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

pub(super) fn validate_object_value(schema: &Map<String, Value>, value: &Value, path: &str) -> Result<(), ValidationError> {
    let object = value.as_object().ok_or_else(|| error("invalid_spec", path, "initial state must be an object"))?;
    if let Some(required) = schema.get("required").and_then(Value::as_array) { for key in required.iter().filter_map(Value::as_str) { if !object.contains_key(key) { return Err(error("invalid_spec", &format!("{path}/{key}"), "required state value is missing")); } } }
    if schema.get("additionalProperties") == Some(&Value::Bool(false)) { if let Some(properties) = schema.get("properties").and_then(Value::as_object) { if let Some(key) = object.keys().find(|key| !properties.contains_key(*key)) { return Err(error("invalid_spec", &format!("{path}/{}", escape_pointer(key)), "unknown state property")); } } }
    if let Some(properties) = schema.get("properties").and_then(Value::as_object) { for (key, child_schema) in properties { if let Some(child) = object.get(key) { validate_value(child_schema, child, &format!("{path}/{}", escape_pointer(key)))?; } } }
    Ok(())
}

pub(super) fn schema_paths(value: &Value, path: &str) -> Vec<String> {
    let Some(properties) = value.get("properties").and_then(Value::as_object) else { return if path.is_empty() { Vec::new() } else { vec![path.to_owned()] }; };
    let mut paths = Vec::new();
    for (key, child) in properties { let child_path = format!("{path}/{}", escape_pointer(key)); paths.push(child_path.clone()); paths.extend(schema_paths(child, &child_path)); }
    paths
}

pub(super) fn schema_types<'a>(schema: &'a Map<String, Value>, path: &str) -> Result<Vec<&'a str>, ValidationError> {
    let value = object_value(schema, "type", path)?;
    let types = schema_type_list(value).unwrap_or_default();
    if types.is_empty() || types.iter().any(|schema_type| !["object", "array", "string", "number", "integer", "boolean", "null"].contains(schema_type)) {
        return Err(error("invalid_spec", &format!("{path}/type"), "unsupported schema type"));
    }
    Ok(types)
}

pub(super) fn schema_type_list(value: &Value) -> Option<Vec<&str>> {
    match value {
        Value::String(schema_type) => Some(vec![schema_type.as_str()]),
        Value::Array(types) if !types.is_empty() && types.iter().all(Value::is_string) => Some(types.iter().filter_map(Value::as_str).collect()),
        _ => None,
    }
}

pub(super) fn value_matches_type(schema_type: &str, value: &Value) -> bool {
    match schema_type {
        "object" => value.is_object(), "array" => value.is_array(), "string" => value.is_string(),
        "number" => value.as_f64().is_some(), "integer" => value.as_i64().is_some() || value.as_u64().is_some(),
        "boolean" => value.is_boolean(), "null" => value.is_null(), _ => false,
    }
}

pub(super) fn schema_at_pointer<'a>(schema: &'a Value, path: &[String]) -> Option<&'a Value> {
    let mut current = schema;
    for segment in path {
        current = current.get("properties")?.get(segment)?;
    }
    Some(current)
}

pub(super) fn validate_summary(value: &Value, schema: &Value) -> Result<(), ValidationError> {
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

pub(super) fn validate_summary_value(value: &Value, path: &str, schema: &Value, require_array: bool) -> Result<(), ValidationError> {
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

pub(super) fn validate_summary_path(pointer: &str, schema: &Value, summary_path: &str, require_array: bool) -> Result<(), ValidationError> {
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

pub(super) fn schema_node_at_path<'a>(schema: &'a Value, pointer: &str) -> Option<&'a Value> {
    let mut current = schema;
    for segment in pointer[1..].split('/').map(|segment| segment.replace("~1", "/").replace("~0", "~")) {
        current = current.get("properties")?.as_object()?.get(&segment)?;
    }
    current.is_object().then_some(current)
}

