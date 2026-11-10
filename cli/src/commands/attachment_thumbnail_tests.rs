// Purpose: send/ask attachment tests against a loopback server with fake sips/ffmpeg: an
// image gets a second JPEG upload whose URL lands beside file_url or the option image URL.
use crate::commands::{
    ask::{prepare_request, AskArgs},
    box_cmd::{
        mock::{Captured, Mock, Reply},
        thumbnail::tests::tools,
    },
    send::{send_request, SendArgs},
};
use crate::{client::HiBossClient, types::SendRequest};
use clap::Parser;
use serde_json::{json, Value};

#[derive(Parser)]
struct Send {
    #[command(flatten)]
    args: SendArgs,
}

#[derive(Parser)]
struct Ask {
    #[command(flatten)]
    args: AskArgs,
}

const FULL: &str = "http://hiboss.test/api/attachments/full";
const THUMB: &str = "http://hiboss.test/api/attachments/thumb";

fn upload(url: &str) -> Reply {
    let body = json!({ "key": "k", "url": url, "filename": "f", "content_type": "image/png", "size": 4 });
    Reply::new("POST", "/api/attachments/upload", 200, body.to_string())
}

async fn send(name: &str, sips: &str, replies: Vec<Reply>) -> (SendRequest, Vec<Captured>) {
    let mock = Mock::start(replies).await;
    let path = mock.directory.join(name);
    std::fs::write(&path, "DATA").unwrap();
    let path = path.to_str().unwrap().to_owned();
    let args = Send::parse_from(["send", "--file", &path, "--verbose", "Shot"]).args;
    let client = HiBossClient::new(&mock.server, "synthetic-box-key");
    let request = send_request(&args, &client, &tools(sips, "missing")).await.unwrap();
    (request, mock.finish().await)
}

fn thumbnail_of(request: &SendRequest) -> Option<&Value> {
    request.metadata.as_ref()?.get("file_thumbnail_url")
}

#[tokio::test]
async fn send_image_uploads_a_jpeg_thumbnail_beside_file_url() {
    let (request, captured) = send("shot.png", "sips-ok", vec![upload(FULL), upload(THUMB)]).await;
    assert_eq!(request.file_url.as_deref(), Some(FULL));
    assert_eq!(thumbnail_of(&request), Some(&Value::from(THUMB)));
    assert!(captured[0].body.contains("filename=\"shot.png\""));
    assert!(captured[1].body.contains("filename=\"thumbnail.jpg\"\r\nContent-Type: image/jpeg"));
}

#[tokio::test]
async fn send_without_tools_or_for_a_non_image_has_no_thumbnail() {
    let (request, captured) = send("shot.png", "missing", vec![upload(FULL)]).await;
    assert_eq!(request.file_url.as_deref(), Some(FULL));
    assert!(thumbnail_of(&request).is_none() && captured.len() == 1);
    let (request, captured) = send("notes.txt", "sips-ok", vec![upload(FULL)]).await;
    assert!(thumbnail_of(&request).is_none() && captured.len() == 1);
}

#[tokio::test]
async fn ask_option_image_and_file_carry_thumbnail_urls() {
    let mock = Mock::start(vec![upload(FULL), upload(THUMB), upload(FULL), upload(THUMB)]).await;
    let path = mock.directory.join("after.png");
    std::fs::write(&path, "DATA").unwrap();
    let path = path.to_str().unwrap().to_owned();
    let image = format!("A={path}");
    let args = Ask::parse_from(["ask", "--option", "A", "--option-image", &image, "--file", &path, "Pick"]).args;
    let choices = args.choice_payload().unwrap();
    let client = HiBossClient::new(&mock.server, "synthetic-box-key");
    let request = prepare_request(&args, &client, &choices, &tools("sips-ok", "missing")).await.unwrap();
    mock.finish().await;
    let metadata = request.metadata.unwrap();
    assert_eq!(metadata["option_media"], json!([{ "label": "A", "url": FULL, "thumbnail_url": THUMB }]));
    assert_eq!(metadata["file_thumbnail_url"], json!(THUMB));
}
