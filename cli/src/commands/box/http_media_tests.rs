// Purpose: Box media HTTP tests for multipart upload, private reads and cache reuse.
// Covers complete and incomplete saves through the command dispatcher and client.
use super::*;
use super::{
    http_tests::{client, execute, idempotency_key, wire_item},
    mock::{Mock, Reply},
    tests::{item, parse},
};
use std::fs;

#[tokio::test]
async fn adds_multipart_media_and_latest_downloads_then_reuses_complete_file() {
    let mock = Mock::start(vec![
        Reply::new("POST", "/api/box/items", 201, wire_item(true)),
        Reply::new("GET", "/api/box/items/latest?kind=image", 200, wire_item(true)),
        Reply::new("GET", "/api/box/items/bx_reference/media", 200, "DATA".into()),
        Reply::new("GET", "/api/box/items/latest?kind=image", 200, wire_item(true)),
    ])
    .await;
    let upload = mock.directory.join("reference.PNG");
    fs::write(&upload, "DATA").unwrap();
    let detected = input::detect(upload.to_str().unwrap()).unwrap();
    assert!(matches!(detected, input::Input::File(_, mime) if mime == "image/png"));
    execute(
        &mock,
        &[
            "box",
            "add",
            upload.to_str().unwrap(),
            "--note",
            "layout",
            "--tag",
            "one",
            "--boss",
            "Boss Name",
        ],
    )
    .await;
    let directory = mock.directory.to_str().unwrap();
    let latest = parse(&["box", "latest", "--kind", "image", "--save", directory, "--json"]);
    run(&latest, &Config::default(), &client(&mock)).await.unwrap();
    assert_eq!(
        fs::read(mock.directory.join("bx_reference.png")).unwrap(),
        b"DATA"
    );
    run(&latest, &Config::default(), &client(&mock)).await.unwrap();
    let requests = mock.finish().await;
    assert_multipart(&requests[0]);
}

fn assert_multipart(upload: &super::mock::Captured) {
    assert!(upload.headers.contains("multipart/form-data; boundary="));
    assert!(upload.body.contains("name=\"meta\""));
    assert!(upload.body.contains("\"source\":\"cli\""));
    assert!(upload.body.contains("\"note\":\"layout\""));
    assert!(upload.body.contains("\"boss\":\"Boss Name\""));
    assert!(upload.body.contains("name=\"file\"; filename=\"reference.PNG\""));
    assert!(upload.body.contains("Content-Type: image/png"));
    assert!(upload.body.contains("DATA"));
    assert_eq!(idempotency_key(upload).len(), 32);
}

#[tokio::test]
async fn show_replaces_incomplete_cached_media_and_reports_saved_path() {
    let mock = Mock::start(vec![
        Reply::new("GET", "/api/box/items/bx_reference", 200, wire_item(true)),
        Reply::new("GET", "/api/box/items/bx_reference/media", 200, "DATA".into()),
    ])
    .await;
    let client = client(&mock);
    let path = mock.directory.join("bx_reference.png");
    fs::write(&path, "bad").unwrap();
    run(
        &parse(&[
            "box",
            "show",
            "bx_reference",
            "--save",
            mock.directory.to_str().unwrap(),
        ]),
        &Config::default(),
        &client,
    )
    .await
    .unwrap();
    assert_eq!(fs::read(path).unwrap(), b"DATA");
    mock.finish().await;
}

#[tokio::test]
async fn incomplete_download_keeps_existing_file_and_removes_partial_file() {
    let mock = Mock::start(vec![Reply::new(
        "GET",
        "/api/box/items/bx_reference/media",
        200,
        "bad".into(),
    )])
    .await;
    let path = mock.directory.join("bx_reference.png");
    fs::write(&path, "old").unwrap();
    let error = media::save_media(
        &client(&mock),
        &item(true),
        &Config::default(),
        Some(&mock.directory),
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("incomplete"));
    assert_eq!(fs::read(&path).unwrap(), b"old");
    assert_eq!(fs::read_dir(&mock.directory).unwrap().count(), 1);
    mock.finish().await;
}

#[tokio::test]
async fn non_media_read_does_not_download_or_create_a_save_directory() {
    let mock = Mock::start(vec![Reply::new(
        "GET",
        "/api/box/items/latest",
        200,
        wire_item(false),
    )])
    .await;
    let directory = mock.directory.join("unused");
    run(
        &parse(&["box", "latest", "--save", directory.to_str().unwrap()]),
        &Config::default(),
        &client(&mock),
    )
    .await
    .unwrap();
    assert!(!directory.exists());
    mock.finish().await;
}
