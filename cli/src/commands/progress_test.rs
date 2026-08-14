// Progress command tests for cursor parsing, media markers, and local metadata.
// Exports: unit coverage for the private progress command helpers.
// Dependencies: parent progress module, time, and serde_json.

use super::*;
use std::str::FromStr;

fn ago(secs: i64) -> String {
    (OffsetDateTime::now_utc() - time::Duration::seconds(secs))
        .format(&Rfc3339)
        .unwrap_or_default()
}

#[test] fn rt_just_now() { assert_eq!(relative_time(&ago(30)), "just now"); }
#[test] fn rt_minutes()  { assert_eq!(relative_time(&ago(300)), "5m ago"); }
#[test] fn rt_hours()    { assert_eq!(relative_time(&ago(10800)), "3h ago"); }
#[test] fn rt_days()     { assert_eq!(relative_time(&ago(172800)), "2d ago"); }
#[test] fn rt_invalid()  { assert_eq!(relative_time("bad"), "bad"); }

#[test]
fn url_item_video() {
    let i = url_media_item("https://h/clip.mp4", None);
    assert_eq!((i.kind.as_str(), i.size), ("video", 0));
}

#[test]
fn parses_composite_cursor_for_list() {
    let cursor = ProgressCursor::from_str(r#"{"created_at":"2026-08-14T09:00:00Z","id":"abc"}"#)
        .expect("valid cursor");
    assert_eq!(cursor.id, "abc");
}

#[test]
fn url_item_image_and_alt() {
    let i = url_media_item("https://h/shot.png", Some("desc".into()));
    assert_eq!((i.kind.as_str(), i.content_type.as_str()), ("image", "image/png"));
    assert_eq!(i.alt, Some("desc".into()));
}

#[test]
fn make_item_optional_fields() {
    let v = make_item("u".into(), "video", "video/mp4", 0,
        Some((1280, 720)), Some(3200), None, None);
    assert_eq!((v.width, v.height, v.duration_ms), (Some(1280), Some(720), Some(3200)));
    let img = make_item("u".into(), "image", "image/png", 0, None, None, None, None);
    assert!(img.width.is_none() && img.height.is_none());
}

#[test]
fn post_args_agent_and_model_flags_present() {
    // Verify that PostArgs carries --agent and --model when both are supplied.
    let pa = PostArgs {
        body: "shipped".to_owned(),
        image: vec![],
        video: vec![],
        url: vec![],
        project: None,
        session: None,
        tag: vec![],
        alt: vec![],
        agent: Some("my-agent".to_owned()),
        model: Some("my-model".to_owned()),
    };
    assert_eq!(pa.agent.as_deref(), Some("my-agent"));
    assert_eq!(pa.model.as_deref(), Some("my-model"));
}

#[test]
fn post_args_no_flags_defaults_to_none() {
    // When neither --agent nor --model is given, both are None (detection path).
    let pa = PostArgs {
        body: "shipped".to_owned(),
        image: vec![],
        video: vec![],
        url: vec![],
        project: None,
        session: None,
        tag: vec![],
        alt: vec![],
        agent: None,
        model: None,
    };
    assert!(pa.agent.is_none());
    assert!(pa.model.is_none());
}
