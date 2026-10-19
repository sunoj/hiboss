// Purpose: HTTP regression coverage for collection mutation commands.
// Verifies resolution, payloads, ordered membership and first-failure handling.
use super::super::{
    http_tests::{client, execute, wire_item},
    mock::{Mock, Reply},
    tests::parse,
};
use crate::config::Config;

#[tokio::test]
async fn creates_and_renames_with_boss_selection() {
    let page = super::tests::page();
    let collection = serde_json::to_string(&page.collections[0]).unwrap();
    let mock = Mock::start(vec![
        Reply::new("POST", "/api/box/collections", 201, collection.clone()),
        Reply::new(
            "GET",
            "/api/box/collections",
            200,
            serde_json::to_string(&page).unwrap(),
        ),
        Reply::new("PATCH", "/api/box/collections/bc_one", 200, collection),
    ])
    .await;
    execute(
        &mock,
        &["box", "collections", "new", "References", "--boss", "boss"],
    )
    .await;
    execute(
        &mock,
        &[
            "box",
            "collections",
            "rename",
            "references",
            "Renamed",
            "--boss",
            "Boss Name",
            "--json",
        ],
    )
    .await;
    let captured = mock.finish().await;
    let create: serde_json::Value = serde_json::from_str(&captured[0].body).unwrap();
    assert_eq!(
        create,
        serde_json::json!({"name": "References", "boss": "boss"})
    );
    let rename: serde_json::Value = serde_json::from_str(&captured[2].body).unwrap();
    assert_eq!(rename, serde_json::json!({"name": "Renamed"}));
}

#[tokio::test]
async fn membership_commands_apply_in_order_and_stop_on_first_failure() {
    for (command, method) in [("add", "PUT"), ("rm", "DELETE")] {
        let mock = Mock::start(vec![
            Reply::new(
                "GET",
                "/api/box/collections",
                200,
                serde_json::to_string(&super::tests::page()).unwrap(),
            ),
            Reply::new(
                method,
                "/api/box/collections/bc_one/items/first",
                200,
                wire_item(false),
            ),
            Reply::new(
                method,
                "/api/box/collections/bc_one/items/denied",
                404,
                "not found".into(),
            ),
        ])
        .await;
        let error = super::super::run(
            &parse(&[
                "box",
                "collections",
                command,
                "bc_one",
                "first",
                "denied",
                "last",
            ]),
            &Config::default(),
            &client(&mock),
        )
        .await
        .unwrap_err()
        .to_string();
        assert!(error.contains("item denied:"));
        assert_eq!(mock.finish().await.len(), 3);
    }
}

#[tokio::test]
async fn new_without_boss_omits_the_optional_field() {
    let mock = Mock::start(vec![Reply::new(
        "POST",
        "/api/box/collections",
        201,
        serde_json::to_string(&super::tests::page().collections[0]).unwrap(),
    )])
    .await;
    execute(
        &mock,
        &["box", "collections", "new", "References", "--json"],
    )
    .await;
    let captured = mock.finish().await;
    let body: serde_json::Value = serde_json::from_str(&captured[0].body).unwrap();
    assert_eq!(body, serde_json::json!({"name": "References"}));
}
