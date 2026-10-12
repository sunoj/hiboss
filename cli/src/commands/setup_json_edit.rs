// Applies hook-setting changes while retaining unmanaged JSON bytes and key order.
// Exports update; existing members are edited by span, new members are appended.
// Dependencies: setup_json_spans, serde_json, setup_hooks ownership detection.

use super::setup_json_spans::Node;
use serde_json::Value;
use std::{error::Error, ops::Range};

pub(super) fn update(raw: &str, target: &Value) -> Result<String, Box<dyn Error>> {
    let node = Node::parse(raw)?;
    let mut output = raw.to_owned();
    output.replace_range(node.start..node.end, &render(raw, &node, target)?);
    Ok(output)
}

fn render(raw: &str, node: &Node, target: &Value) -> Result<String, Box<dyn Error>> {
    let old: Value = serde_json::from_str(&raw[node.start..node.end])?;
    if old == *target {
        return Ok(raw[node.start..node.end].to_owned());
    }
    if !(old.is_object() && target.is_object() || old.is_array() && target.is_array()) {
        return Ok(serde_json::to_string(target)?);
    }
    let (kept, additions) = align(raw, node, target)?;
    let mut edits = Vec::new();
    for (index, value) in kept.iter().enumerate() {
        if let Some(value) = value {
            let child = &node.members[index].node;
            edits.push((child.start..child.end, render(raw, child, value)?));
        }
    }
    edits.extend(
        deletions(node, &kept)
            .into_iter()
            .map(|range| (range, String::new())),
    );
    edits.sort_by_key(|(range, _)| range.start);
    let mut output = raw[node.start..node.end].to_owned();
    for (range, replacement) in edits.into_iter().rev() {
        output.replace_range(
            range.start - node.start..range.end - node.start,
            &replacement,
        );
    }
    if !additions.is_empty() {
        let close = output.len() - 1;
        let at = output[..close].trim_end().len();
        let comma = if kept.iter().any(Option::is_some) {
            ","
        } else {
            ""
        };
        output.insert_str(at, &format!("{comma}{}", additions.join(",")));
    }
    Ok(output)
}

type Alignment<'a> = (Vec<Option<&'a Value>>, Vec<String>);

fn align<'a>(raw: &str, node: &Node, target: &'a Value) -> Result<Alignment<'a>, Box<dyn Error>> {
    let mut kept = vec![None; node.members.len()];
    let mut additions = Vec::new();
    if let Some(object) = target.as_object() {
        for (index, member) in node.members.iter().enumerate() {
            kept[index] = member.key.as_ref().and_then(|key| object.get(key));
        }
        for (key, value) in object {
            if !node
                .members
                .iter()
                .any(|member| member.key.as_ref() == Some(key))
            {
                additions.push(format!(
                    "{}:{}",
                    serde_json::to_string(key)?,
                    serde_json::to_string(value)?
                ));
            }
        }
    } else if let Some(array) = target.as_array() {
        let mut cursor = 0;
        for value in array {
            let mut found = None;
            for index in cursor..node.members.len() {
                let child = &node.members[index].node;
                let old: Value = serde_json::from_str(&raw[child.start..child.end])?;
                if compatible(&old, value) {
                    found = Some(index);
                    break;
                }
            }
            if let Some(index) = found {
                kept[index] = Some(value);
                cursor = index + 1;
            } else {
                additions.push(serde_json::to_string(value)?);
            }
        }
    }
    Ok((kept, additions))
}

fn compatible(old: &Value, new: &Value) -> bool {
    if old == new {
        return true;
    }
    if super::setup_hooks::is_hiboss_hook(old) && super::setup_hooks::is_hiboss_hook(new) {
        return true;
    }
    let without_managed = |value: &Value| {
        let mut value = value.clone();
        if let Some(hooks) = value.get_mut("hooks").and_then(Value::as_array_mut) {
            hooks.retain(|hook| !super::setup_hooks::is_hiboss_hook(hook));
        }
        value
    };
    old.get("hooks").is_some()
        && new.get("hooks").is_some()
        && without_managed(old) == without_managed(new)
}

fn deletions(node: &Node, kept: &[Option<&Value>]) -> Vec<Range<usize>> {
    let mut ranges = Vec::new();
    let mut index = 0;
    while index < kept.len() {
        if kept[index].is_some() {
            index += 1;
            continue;
        }
        let first = index;
        while index < kept.len() && kept[index].is_none() {
            index += 1;
        }
        let last = index - 1;
        let range = if index < kept.len() {
            node.members[first].start..node.members[index].start
        } else if first > 0 {
            node.members[first - 1].node.end..node.members[last].node.end
        } else {
            node.members[first].start..node.members[last].node.end
        };
        ranges.push(range);
    }
    ranges
}

#[cfg(test)]
#[path = "setup_json_tests.rs"]
mod tests;
