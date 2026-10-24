// Purpose: Thumbnail tests with fake sips/ffmpeg scripts: present, missing, oversize, and
// the multipart upload with and without the `thumbnail` part.
use super::{for_upload, Tools, MAX_BYTES};
use crate::commands::box_cmd::{
    args::BoxCommand,
    http_tests::{client, wire_item},
    mock::{Mock, Reply},
    tests::parse,
};
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, sync::OnceLock};

const SMALL_SIPS: &str = r"printf '\377\330\377sips' > $out";
const SMALL_FFMPEG: &str = r"printf '\377\330\377ffmpeg' > $out";
const BIG: &str = r"{ printf '\377\330\377'; head -c 300000 /dev/zero; } > $out";

/// Fake tools are written once, before any test spawns them, to avoid ETXTBSY races.
fn fakes() -> &'static PathBuf {
    static DIR: OnceLock<PathBuf> = OnceLock::new();
    DIR.get_or_init(|| {
        let dir = std::env::temp_dir().join(format!("hiboss-thumb-fakes-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let shrink = format!(
            "case \" $* \" in *' formatOptions 50 '*|*' -q:v 9 '*) {SMALL_SIPS};; *) {BIG};; esac"
        );
        let png = r"printf '\211PNG\r\n\032\n' > $out";
        for (name, body) in [
            ("sips-ok", SMALL_SIPS),
            ("ffmpeg-ok", SMALL_FFMPEG),
            ("big", BIG),
            ("shrink", shrink.as_str()),
            ("png", png),
            ("fail", "exit 1"),
        ] {
            let path = dir.join(name);
            fs::write(&path, format!("#!/bin/sh\nfor out; do :; done\n{body}\n")).unwrap();
            fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
        }
        dir
    })
}

fn tools(sips: &str, ffmpeg: &str) -> Tools {
    Tools {
        sips: fakes().join(sips),
        ffmpeg: fakes().join(ffmpeg),
    }
}

fn input(name: &str) -> PathBuf {
    let path = fakes().join(name);
    fs::write(&path, "DATA").unwrap();
    path
}

#[test]
fn image_uses_sips_then_ffmpeg_and_video_uses_ffmpeg() {
    let image = input("photo.png");
    let video = input("clip.mp4");
    let sips = for_upload(&image, "image/png", &tools("sips-ok", "ffmpeg-ok"), false);
    assert_eq!(sips.unwrap(), b"\xFF\xD8\xFFsips");
    let fallback = for_upload(&image, "image/png", &tools("missing", "ffmpeg-ok"), false);
    assert_eq!(fallback.unwrap(), b"\xFF\xD8\xFFffmpeg");
    let poster = for_upload(&video, "video/mp4", &tools("sips-ok", "ffmpeg-ok"), false);
    assert_eq!(poster.unwrap(), b"\xFF\xD8\xFFffmpeg");
}

#[test]
fn missing_or_failing_tools_and_non_media_give_no_thumbnail() {
    let image = input("missing.png");
    assert!(for_upload(&image, "image/png", &tools("missing", "missing"), true).is_none());
    assert!(for_upload(&image, "image/png", &tools("fail", "fail"), true).is_none());
    assert!(for_upload(&image, "image/png", &tools("png", "png"), false).is_none());
    let file = input("notes.txt");
    assert!(for_upload(&file, "text/plain", &tools("sips-ok", "ffmpeg-ok"), false).is_none());
}

#[test]
fn oversize_retries_at_lower_quality_then_is_dropped() {
    let image = input("large.png");
    let retried = for_upload(&image, "image/png", &tools("shrink", "missing"), false).unwrap();
    assert!(retried.len() <= MAX_BYTES);
    assert!(for_upload(&image, "image/png", &tools("big", "big"), true).is_none());
    let video = input("large.mp4");
    assert!(for_upload(&video, "video/mp4", &tools("missing", "big"), false).is_none());
}

async fn upload(tools: &Tools) -> String {
    let mock = Mock::start(vec![Reply::new("POST", "/api/box/items", 201, wire_item(true))]).await;
    let path = mock.directory.join("shot.png");
    fs::write(&path, "DATA").unwrap();
    let BoxCommand::Add(args) = parse(&["box", "add", path.to_str().unwrap(), "--verbose"]).command
    else {
        unreachable!("add parses as BoxCommand::Add")
    };
    let item = super::super::add(&args, &client(&mock), tools).await.unwrap();
    assert_eq!(item.id, "bx_reference");
    mock.finish().await.remove(0).body
}

#[tokio::test]
async fn upload_attaches_thumbnail_part_when_a_tool_succeeds() {
    let body = upload(&tools("sips-ok", "missing")).await;
    assert!(body.contains("name=\"file\"; filename=\"shot.png\""));
    assert!(body.contains("name=\"thumbnail\"; filename=\"thumbnail.jpg\"\r\nContent-Type: image/jpeg"));
    assert!(body.contains("sips"));
}

#[tokio::test]
async fn upload_succeeds_without_thumbnail_part_when_tools_are_missing() {
    let body = upload(&tools("missing", "missing")).await;
    assert!(body.contains("name=\"file\"; filename=\"shot.png\""));
    assert!(!body.contains("name=\"thumbnail\""));
}
