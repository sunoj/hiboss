// Purpose: Parse panel JSON while detecting duplicate object keys.
// Exports: parse_unique_json.
// Dependencies: serde deserialization and serde_json values.

use serde::de::{DeserializeSeed, Deserializer, MapAccess, SeqAccess, Visitor};
use serde_json::{Map, Value};
use std::fmt;

pub fn parse_unique_json(body: &str) -> Result<Value, String> {
    let mut deserializer = serde_json::Deserializer::from_str(body);
    let value = JsonSeed.deserialize(&mut deserializer).map_err(|error| error.to_string())?;
    deserializer.end().map_err(|error| error.to_string())?;
    Ok(value)
}

struct JsonSeed;

impl<'de> DeserializeSeed<'de> for JsonSeed {
    type Value = Value;

    fn deserialize<D>(self, deserializer: D) -> Result<Value, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_any(JsonVisitor)
    }
}

struct JsonVisitor;

impl<'de> Visitor<'de> for JsonVisitor {
    type Value = Value;

    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result { formatter.write_str("a JSON value") }
    fn visit_bool<E>(self, value: bool) -> Result<Value, E> { Ok(Value::Bool(value)) }
    fn visit_i64<E>(self, value: i64) -> Result<Value, E> where E: serde::de::Error { Ok(Value::Number(value.into())) }
    fn visit_u64<E>(self, value: u64) -> Result<Value, E> where E: serde::de::Error { Ok(Value::Number(value.into())) }
    fn visit_f64<E>(self, value: f64) -> Result<Value, E> where E: serde::de::Error { serde_json::Number::from_f64(value).map(Value::Number).ok_or_else(|| E::custom("non-finite JSON number")) }
    fn visit_str<E>(self, value: &str) -> Result<Value, E> { Ok(Value::String(value.to_owned())) }
    fn visit_string<E>(self, value: String) -> Result<Value, E> { Ok(Value::String(value)) }
    fn visit_unit<E>(self) -> Result<Value, E> { Ok(Value::Null) }
    fn visit_none<E>(self) -> Result<Value, E> { Ok(Value::Null) }
    fn visit_some<D>(self, deserializer: D) -> Result<Value, D::Error> where D: Deserializer<'de> { JsonSeed.deserialize(deserializer) }
    fn visit_seq<A>(self, mut access: A) -> Result<Value, A::Error> where A: SeqAccess<'de> { let mut values = Vec::new(); while let Some(value) = access.next_element_seed(JsonSeed)? { values.push(value); } Ok(Value::Array(values)) }
    fn visit_map<A>(self, mut access: A) -> Result<Value, A::Error> where A: MapAccess<'de> { let mut values = Map::new(); while let Some(key) = access.next_key::<String>()? { if values.contains_key(&key) { return Err(serde::de::Error::custom(format!("duplicate JSON key \"{key}\""))); } let value = access.next_value_seed(JsonSeed)?; values.insert(key, value); } Ok(Value::Object(values)) }
}

#[cfg(test)]
mod tests {
    use super::parse_unique_json;

    #[test]
    fn parses_nested_json() { assert_eq!(parse_unique_json(r#"{"a":{"b":[true,null]}}"#).expect("JSON" )["a"]["b"][0], true); }

    #[test]
    fn rejects_duplicate_keys() { let error = parse_unique_json(r#"{"a":1,"a":2}"#).expect_err("duplicate"); assert!(error.contains("duplicate JSON key")); }
}
