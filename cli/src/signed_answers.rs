// Comparison of a form reply's stored answers with the answers its boss signed.
// Exports same_answers; numbers compare by value so 1.0 (client) equals 1 (server copy).
// Dependencies: serde_json.

use serde_json::Value;

/// Equal JSON, comparing numbers by value: the client may encode `1.0` where the server's
/// stored copy reads `1`.
pub(crate) fn same_answers(stored: Option<&Value>, signed: Option<&Value>) -> bool {
    match (stored, signed) {
        (None, None) => true,
        (Some(stored), Some(signed)) => same_json(stored, signed),
        _ => false,
    }
}

fn same_json(left: &Value, right: &Value) -> bool {
    match (left, right) {
        (Value::Number(a), Value::Number(b)) => a.as_f64() == b.as_f64(),
        (Value::Array(a), Value::Array(b)) => a.len() == b.len() && a.iter().zip(b).all(|(x, y)| same_json(x, y)),
        (Value::Object(a), Value::Object(b)) => a.len() == b.len()
            && a.iter().all(|(key, value)| b.get(key).is_some_and(|other| same_json(value, other))),
        _ => left == right,
    }
}

