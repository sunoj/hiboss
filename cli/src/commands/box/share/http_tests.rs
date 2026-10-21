// Purpose: Share-link HTTP tests: request paths and bodies, rendered output, ttl bounds and
// the `box add --share` partial failure that keeps the added item.
use super::super::{
    BoxArgs,
    http_tests::{client, execute, wire_item},
    mock::{Mock, Reply},
    run,
    tests::parse,
};
use super::*;
use crate::config::Config;
use clap::{CommandFactory, Parser};

const URL: &str = "https://hiboss.example/s/synthetic-share-token";

fn created() -> String {
    serde_json::json!({
        "id": "bs_one", "itemId": "bx_reference", "url": URL,
        "expiresAt": "2026-10-28T00:00:00Z", "createdAt": "2026-10-21T00:00:00Z"
    })
    .to_string()
}

fn body(request: &super::super::mock::Captured) -> serde_json::Value {
    serde_json::from_str(&request.body).unwrap()
}

#[tokio::test]
async fn share_posts_ttl_seconds_and_defaults_to_server_lifetime() {
    let path = "/api/box/items/bx_reference/shares";
    let mock = Mock::start(vec![
        Reply::new("POST", path, 201, created()),
        Reply::new("POST", path, 201, created()),
    ])
    .await;
    execute(&mock, &["box", "share", "bx_reference", "--ttl", "12h"]).await;
    execute(&mock, &["box", "share", "bx_reference", "--json"]).await;
    let requests = mock.finish().await;
    assert_eq!(
        body(&requests[0]),
        serde_json::json!({ "ttlSeconds": 43200 })
    );
    assert_eq!(body(&requests[1]), serde_json::json!({}));
}

#[test]
fn created_share_prints_url_bare_labelled_or_as_json() {
    let share: BoxShare = serde_json::from_str(&created()).unwrap();
    assert_eq!(render_created(&share, false, false).unwrap(), URL);
    assert_eq!(
        render_created(&share, false, true).unwrap(),
        format!("share: {URL}")
    );
    let json: serde_json::Value =
        serde_json::from_str(&render_created(&share, true, true).unwrap()).unwrap();
    assert_eq!(json["url"], URL);
    assert_eq!(json["expiresAt"], "2026-10-28T00:00:00Z");
}

#[tokio::test]
async fn shares_lists_records_without_tokens_and_unshare_revokes() {
    let list = serde_json::json!({ "shares": [{
        "id": "bs_one", "itemId": "bx_reference", "createdAt": "2026-10-21T00:00:00Z",
        "expiresAt": "2026-10-28T00:00:00Z", "revokedAt": null, "createdBy": "boss",
        "viewCount": 3, "lastViewedAt": null, "active": true
    }]})
    .to_string();
    let mock = Mock::start(vec![
        Reply::new(
            "GET",
            "/api/box/items/bx_reference/shares",
            200,
            list.clone(),
        ),
        Reply::new(
            "GET",
            "/api/box/items/bx_reference/shares",
            200,
            list.clone(),
        ),
        Reply::new("DELETE", "/api/box/shares/bs_one", 204, String::new()),
    ])
    .await;
    execute(&mock, &["box", "shares", "bx_reference"]).await;
    execute(&mock, &["box", "shares", "bx_reference", "--json"]).await;
    execute(&mock, &["box", "unshare", "bs_one"]).await;
    mock.finish().await;
    let parsed: BoxShareList = serde_json::from_str(&list).unwrap();
    let table = render_table(&parsed.shares);
    let row = table.lines().nth(1).unwrap();
    assert!(table.starts_with("ID"));
    assert!(row.starts_with("bs_one") && row.contains("2026-10-28T00:00:00Z"));
    assert!(row.contains("  3  yes"));
}

#[tokio::test]
async fn add_with_share_creates_item_then_link() {
    let mock = Mock::start(vec![
        Reply::new("POST", "/api/box/items", 201, wire_item(false)),
        Reply::new("POST", "/api/box/items/bx_reference/shares", 201, created()),
    ])
    .await;
    execute(&mock, &["box", "add", "hello", "--share", "--ttl", "2d"]).await;
    let requests = mock.finish().await;
    assert_eq!(body(&requests[0])["text"], "hello");
    assert_eq!(
        body(&requests[1]),
        serde_json::json!({ "ttlSeconds": 172800 })
    );
}

#[tokio::test]
async fn add_share_failure_keeps_item_and_fails_with_share_error() {
    let mock = Mock::start(vec![
        Reply::new("POST", "/api/box/items", 201, wire_item(false)),
        Reply::new(
            "POST",
            "/api/box/items/bx_reference/shares",
            400,
            r#"{"error":"ttlSeconds out of range synthetic-box-key"}"#.into(),
        ),
    ])
    .await;
    let error = run(
        &parse(&["box", "add", "hello", "--share"]),
        &Config::default(),
        &client(&mock),
    )
    .await
    .unwrap_err()
    .to_string();
    assert_eq!(mock.finish().await.len(), 2, "no rollback request");
    assert!(error.contains("bx_reference was added, but sharing it failed"));
    assert!(error.contains("ttlSeconds out of range"));
    assert!(!error.contains("synthetic-box-key"));
}

#[tokio::test]
async fn share_access_errors_surface_with_status() {
    let mock = Mock::start(vec![
        Reply::new(
            "POST",
            "/api/box/items/bx_other/shares",
            404,
            r#"{"error":"not found"}"#.into(),
        ),
        Reply::new(
            "DELETE",
            "/api/box/shares/bs_other",
            404,
            r#"{"error":"not found"}"#.into(),
        ),
    ])
    .await;
    for arguments in [["box", "share", "bx_other"], ["box", "unshare", "bs_other"]] {
        let error = run(&parse(&arguments), &Config::default(), &client(&mock))
            .await
            .unwrap_err()
            .to_string();
        assert!(
            error.contains("404") && error.contains("access denied"),
            "{error}"
        );
    }
    mock.finish().await;
}

#[derive(Parser)]
struct CommandLine {
    #[command(flatten)]
    args: BoxArgs,
}

#[test]
fn ttl_bounds_and_share_requirement_are_enforced_locally() {
    for arguments in [
        &["box", "share", "bx_reference", "--ttl", "30m"][..],
        &["box", "share", "bx_reference", "--ttl", "31d"],
        &["box", "share", "bx_reference", "--ttl", "3599"],
        &["box", "add", "hello", "--share", "--ttl", "0d"],
        &["box", "add", "hello", "--ttl", "1d"],
    ] {
        assert!(
            CommandLine::try_parse_from(arguments).is_err(),
            "{arguments:?}"
        );
    }
    let error = CommandLine::try_parse_from(["box", "share", "x", "--ttl", "31d"])
        .err()
        .unwrap()
        .to_string();
    assert!(error.contains("between 1h and 30d"), "{error}");
}

#[test]
fn help_states_who_can_view_a_shared_item() {
    let mut command = CommandLine::command();
    let help = command
        .find_subcommand_mut("share")
        .unwrap()
        .render_long_help()
        .to_string();
    assert!(help.contains(VISIBILITY), "{help}");
    let add = command
        .find_subcommand_mut("add")
        .unwrap()
        .render_help()
        .to_string();
    assert!(
        add.contains("anyone with the link can view the item"),
        "{add}"
    );
}
