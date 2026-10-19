// Purpose: Mock HTTP coverage for collection filters, resolution ordering and read output.
// Depends on the existing timeout-bounded Box mock server and command fixtures.
use super::super::{
    http_tests::{client, execute, wire_item},
    mock::{Mock, Reply},
    tests::parse,
};
use super::*;
use crate::config::Config;

#[tokio::test]
async fn list_latest_search_send_liked_and_collection_filters() {
    let page = serde_json::json!({"items": [], "next_cursor": null}).to_string();
    let mock = Mock::start(vec![
        Reply::new(
            "GET",
            "/api/box/items?liked=1&collection=My+References",
            200,
            page.clone(),
        ),
        Reply::new(
            "GET",
            "/api/box/items/latest?liked=1&collection=bc_one",
            200,
            wire_item(false),
        ),
        Reply::new(
            "GET",
            "/api/box/items/search?liked=1&collection=bc_one&q=needle",
            200,
            page,
        ),
    ])
    .await;
    execute(
        &mock,
        &["box", "list", "--liked", "--collection", "My References"],
    )
    .await;
    execute(&mock, &["box", "latest", "--liked", "--collection", "bc_one"]).await;
    execute(
        &mock,
        &["box", "search", "needle", "--liked", "--collection", "bc_one"],
    )
    .await;
    assert_eq!(mock.finish().await.len(), 3);
}

#[tokio::test]
async fn add_resolves_repeatable_collections_before_creation_then_adds_membership() {
    let mut page = super::tests::page();
    let mut other: Collection =
        serde_json::from_value(serde_json::to_value(&page.collections[0]).unwrap()).unwrap();
    other.id = "bc_two".into();
    other.name = "Second".into();
    page.collections.push(other);
    let mock = Mock::start(vec![
        Reply::new(
            "GET",
            "/api/box/collections",
            200,
            serde_json::to_string(&page).unwrap(),
        ),
        Reply::new("POST", "/api/box/items", 201, wire_item(false)),
        Reply::new(
            "PUT",
            "/api/box/collections/bc_one/items/bx_reference",
            200,
            wire_item(false),
        ),
        Reply::new(
            "PUT",
            "/api/box/collections/bc_two/items/bx_reference",
            200,
            wire_item(false),
        ),
    ])
    .await;
    execute(
        &mock,
        &[
            "box",
            "add",
            "text",
            "--boss",
            "boss",
            "--collection",
            "references",
            "--collection",
            "bc_two",
            "--json",
        ],
    )
    .await;
    assert_eq!(mock.finish().await.len(), 4);
}

#[tokio::test]
async fn unknown_or_ambiguous_collection_creates_nothing() {
    for ambiguous in [false, true] {
        let mut page = super::tests::page();
        if ambiguous {
            let mut other: Collection =
                serde_json::from_value(serde_json::to_value(&page.collections[0]).unwrap()).unwrap();
            other.id = "bc_two".into();
            other.boss_id = "other".into();
            page.collections.push(other);
        }
        let mock = Mock::start(vec![Reply::new(
            "GET",
            "/api/box/collections",
            200,
            serde_json::to_string(&page).unwrap(),
        )])
        .await;
        let name = if ambiguous { "References" } else { "missing" };
        let error = super::super::run(
            &parse(&["box", "add", "text", "--collection", name]),
            &Config::default(),
            &client(&mock),
        )
        .await
        .unwrap_err()
        .to_string();
        assert!(error.contains(if ambiguous {
            "Ambiguous"
        } else {
            "valid names: References"
        }));
        assert_eq!(mock.finish().await.len(), 1);
    }
}

#[tokio::test]
async fn collections_command_supports_boss_and_json() {
    let body = serde_json::to_string(&super::tests::page()).unwrap();
    let mock = Mock::start(vec![
        Reply::new("GET", "/api/box/collections", 200, body.clone()),
        Reply::new("GET", "/api/box/collections", 200, body),
    ])
    .await;
    execute(&mock, &["box", "collections", "--boss", "Boss Name"]).await;
    execute(&mock, &["box", "collections", "--boss", "boss", "--json"]).await;
    assert_eq!(mock.finish().await.len(), 2);
}

#[tokio::test]
async fn metadata_lookup_is_skipped_for_json_and_older_items() {
    let mock = Mock::start(vec![Reply::new(
        "GET",
        "/api/box/collections",
        200,
        serde_json::to_string(&super::tests::page()).unwrap(),
    )])
    .await;
    let mut item = super::super::tests::item(false);
    assert!(
        for_items(std::slice::from_ref(&item), false, &client(&mock))
            .await
            .unwrap()
            .is_empty()
    );
    item.collection_ids = vec!["bc_one".into()];
    assert!(
        for_items(std::slice::from_ref(&item), true, &client(&mock))
            .await
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        for_items(&[item], false, &client(&mock)).await.unwrap()[0].name,
        "References"
    );
    assert_eq!(mock.finish().await.len(), 1);
}

#[tokio::test]
async fn text_reads_fetch_collection_names_for_list_latest_and_show() {
    let mut item = super::super::tests::item(false);
    item.liked = true;
    item.collection_ids = vec!["bc_one".into()];
    let wire = serde_json::to_string(&item).unwrap();
    let page = serde_json::json!({"items": [item], "next_cursor": null}).to_string();
    for (path, body, args) in [
        ("/api/box/items", page, vec!["box", "list"]),
        ("/api/box/items/latest", wire.clone(), vec!["box", "latest"]),
        (
            "/api/box/items/bx_reference",
            wire,
            vec!["box", "show", "bx_reference"],
        ),
    ] {
        let mock = Mock::start(vec![
            Reply::new("GET", path, 200, body),
            Reply::new(
                "GET",
                "/api/box/collections",
                200,
                serde_json::to_string(&super::tests::page()).unwrap(),
            ),
        ])
        .await;
        execute(&mock, &args).await;
        assert_eq!(mock.finish().await.len(), 2);
    }
}
