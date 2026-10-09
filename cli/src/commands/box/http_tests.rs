// Purpose: Box command HTTP tests for JSON/multipart ingestion and private media reads.
// Covers pagination, cache reuse, incomplete downloads, purge and credential redaction.
use super::*;
use super::{
    mock::{Mock, Reply},
    tests::{item, parse},
};
use std::fs;

pub(super) fn wire_item(media: bool) -> String {
    serde_json::to_string(&item(media)).unwrap()
}

pub(super) fn client(mock: &Mock) -> HiBossClient {
    HiBossClient::new(&mock.server, "synthetic-box-key")
}

pub(super) async fn execute(mock: &Mock, arguments: &[&str]) {
    run(&parse(arguments), &Config::default(), &client(mock))
        .await
        .unwrap();
}

pub(super) fn idempotency_key(request: &super::mock::Captured) -> String {
    request
        .headers
        .lines()
        .find_map(|line| {
            line.to_ascii_lowercase()
                .strip_prefix("idempotency-key: ")
                .map(str::to_owned)
        })
        .expect("fresh idempotency header")
}

#[tokio::test]
async fn adds_text_and_links_as_json_with_fresh_keys() {
    let mock = Mock::start(vec![
        Reply::new("POST", "/api/box/items", 201, wire_item(false)),
        Reply::new("POST", "/api/box/items", 201, wire_item(false)),
    ])
    .await;
    execute(
        &mock,
        &[
            "box",
            "add",
            "hello",
            "--note",
            "layout",
            "--project",
            "demo",
            "--tag",
            "one",
            "--boss",
            "Boss Name",
        ],
    )
    .await;
    execute(&mock, &["box", "add", "https://example.invalid", "--json"]).await;
    let requests = mock.finish().await;
    let text: serde_json::Value = serde_json::from_str(&requests[0].body).unwrap();
    assert_eq!(text["text"], "hello");
    assert!(text.get("url").is_none());
    assert_eq!(text["source"], "cli");
    assert_eq!(text["boss"], "Boss Name");
    assert_eq!(text["note"], "layout");
    assert_eq!(text["project"], "demo");
    assert_eq!(text["tags"], serde_json::json!(["one"]));
    let link: serde_json::Value = serde_json::from_str(&requests[1].body).unwrap();
    assert_eq!(link["url"], "https://example.invalid");
    assert!(link.get("text").is_none());
    assert!(link.get("boss").is_none());
    assert_ne!(idempotency_key(&requests[0]), idempotency_key(&requests[1]));
}

#[tokio::test]
async fn list_and_search_pass_next_cursor_verbatim_with_filters() {
    let page = serde_json::json!({"items": [item(false)], "next_cursor": "opaque_-"}).to_string();
    let mock = Mock::start(page_replies(page)).await;
    let client = client(&mock);
    let page = client
        .list_box_items(
            &crate::box_types::BoxFilter {
                kind: Some(crate::box_types::BoxKind::Text),
                since: Some("1h"),
                project: Some("demo"),
                boss: Some("Boss Name"),
                by: None,
                limit: Some(1),
                cursor: None,
            },
            None,
        )
        .await
        .unwrap();
    let filter = crate::box_types::BoxFilter {
        cursor: page.next_cursor.as_deref(),
        ..Default::default()
    };
    assert_eq!(client.list_box_items(&filter, None).await.unwrap().items.len(), 1);
    let searched = client
        .list_box_items(&filter, Some("layout words"))
        .await
        .unwrap();
    assert_eq!(searched.items.len(), 1);
    execute(&mock, &["box", "rm", "bx_reference", "--purge"]).await;
    mock.finish().await;
}

fn page_replies(page: String) -> Vec<Reply> {
    vec![
        Reply::new(
            "GET",
            "/api/box/items?kind=text&since=1h&project=demo&boss=Boss+Name&limit=1",
            200,
            page.clone(),
        ),
        Reply::new("GET", "/api/box/items?cursor=opaque_-", 200, page.clone()),
        Reply::new(
            "GET",
            "/api/box/items/search?cursor=opaque_-&q=layout+words",
            200,
            page,
        ),
        Reply::new(
            "DELETE",
            "/api/box/items/bx_reference?purge=1",
            204,
            String::new(),
        ),
    ]
}

#[tokio::test]
async fn list_latest_and_search_transmit_by_flags() {
    let page = serde_json::json!({"items": [item(false)], "next_cursor": null}).to_string();
    let mock = Mock::start(vec![
        Reply::new("GET", "/api/box/items?by=boss", 200, page.clone()),
        Reply::new(
            "GET",
            "/api/box/items/latest?by=agent",
            200,
            wire_item(false),
        ),
        Reply::new("GET", "/api/box/items/search?by=boss&q=needle", 200, page),
    ])
    .await;
    execute(&mock, &["box", "list", "--by", "boss"]).await;
    execute(&mock, &["box", "latest", "--by", "agent"]).await;
    execute(&mock, &["box", "search", "needle", "--by", "boss"]).await;
    mock.finish().await;
}

#[tokio::test]
async fn access_error_redacts_credential_and_explains_agent_ownership() {
    let mock = Mock::start(vec![Reply::new(
        "POST",
        "/api/box/items",
        404,
        "synthetic-box-key".into(),
    )])
    .await;
    let error = run(
        &parse(&["box", "add", "text"]),
        &Config::default(),
        &client(&mock),
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(error.contains("only their own items"));
    assert!(!error.contains("boss token only"));
    assert!(error.contains("[redacted]"));
    assert!(!error.contains("synthetic-box-key"));
    mock.finish().await;
}

#[tokio::test]
async fn invalid_local_files_are_rejected_before_http() {
    let mock = Mock::start(Vec::new()).await;
    let path = mock.directory.join("empty.png");
    fs::write(&path, "").unwrap();
    assert!(
        input::detect(path.to_str().unwrap())
            .unwrap_err()
            .to_string()
            .contains("1 to")
    );
    assert!(
        input::detect(mock.directory.to_str().unwrap())
            .unwrap_err()
            .to_string()
            .contains("regular file")
    );
    mock.finish().await;
}
