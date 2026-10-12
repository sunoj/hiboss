// Records byte spans in validated settings JSON without changing its formatting.
// Exports Node and Member for targeted lifecycle-setting edits.
// Dependencies: serde_json and byte-level scanning of UTF-8 JSON.

use serde_json::Value;
use std::{collections::HashSet, error::Error};

pub(super) struct Member {
    pub key: Option<String>,
    pub start: usize,
    pub node: Node,
}

pub(super) struct Node {
    pub start: usize,
    pub end: usize,
    pub members: Vec<Member>,
}

impl Node {
    pub fn parse(raw: &str) -> Result<Self, Box<dyn Error>> {
        serde_json::from_str::<Value>(raw)?;
        parse_node(raw, &mut 0)
    }
}

fn whitespace(raw: &str, cursor: &mut usize) {
    while raw
        .as_bytes()
        .get(*cursor)
        .is_some_and(u8::is_ascii_whitespace)
    {
        *cursor += 1;
    }
}

fn string_end(raw: &str, cursor: &mut usize) {
    *cursor += 1;
    while let Some(byte) = raw.as_bytes().get(*cursor) {
        *cursor += 1;
        match byte {
            b'"' => break,
            b'\\' => *cursor += 1,
            _ => {}
        }
    }
}

fn parse_node(raw: &str, cursor: &mut usize) -> Result<Node, Box<dyn Error>> {
    whitespace(raw, cursor);
    let start = *cursor;
    let mut members = Vec::new();
    match raw.as_bytes().get(*cursor) {
        Some(b'{' | b'[') => members = parse_members(raw, cursor)?,
        Some(b'"') => string_end(raw, cursor),
        Some(_) => {
            while raw
                .as_bytes()
                .get(*cursor)
                .is_some_and(|byte| !byte.is_ascii_whitespace() && !b",]}".contains(byte))
            {
                *cursor += 1;
            }
        }
        None => return Err("Missing JSON value".into()),
    }
    Ok(Node {
        start,
        end: *cursor,
        members,
    })
}

fn parse_members(raw: &str, cursor: &mut usize) -> Result<Vec<Member>, Box<dyn Error>> {
    let object = raw.as_bytes()[*cursor] == b'{';
    let close = if object { b'}' } else { b']' };
    *cursor += 1;
    let mut members = Vec::new();
    let mut keys = HashSet::new();
    loop {
        whitespace(raw, cursor);
        if raw.as_bytes().get(*cursor) == Some(&close) {
            break;
        }
        let start = *cursor;
        let key = if object {
            string_end(raw, cursor);
            let key: String = serde_json::from_str(&raw[start..*cursor])?;
            if !keys.insert(key.clone()) {
                return Err("Duplicate settings key; repair settings first".into());
            }
            whitespace(raw, cursor);
            *cursor += 1;
            Some(key)
        } else {
            None
        };
        let node = parse_node(raw, cursor)?;
        members.push(Member { key, start, node });
        whitespace(raw, cursor);
        if raw.as_bytes().get(*cursor) != Some(&b',') {
            break;
        }
        *cursor += 1;
    }
    *cursor += 1;
    Ok(members)
}
