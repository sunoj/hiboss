// Purpose: Detect Box text, HTTP links and local files before ingestion.
// Exports: Input, detect, mime_for_path; uses existing MIME mappings and filesystem metadata.
use crate::box_types::BoxKind;
use std::{
    error::Error,
    path::{Path, PathBuf},
};

#[derive(Debug, PartialEq, Eq)]
pub(super) enum Input {
    Text,
    Link,
    File(PathBuf, String),
}

pub(super) fn detect(content: &str) -> Result<Input, Box<dyn Error>> {
    if let Ok(url) = reqwest::Url::parse(content) {
        if matches!(url.scheme(), "http" | "https") && url.host_str().is_some() {
            return Ok(Input::Link);
        }
    }
    let path = Path::new(content);
    match std::fs::metadata(path) {
        Ok(metadata) => {
            if !metadata.is_file() {
                return Err(format!("{} is not a regular file", path.display()).into());
            }
            let mime = mime_for_path(path);
            let limit = if kind_for_mime(&mime) == BoxKind::Image {
                10
            } else {
                50
            } * 1024
                * 1024;
            if metadata.len() == 0 || metadata.len() > limit {
                return Err(format!("file must contain 1 to {limit} bytes").into());
            }
            Ok(Input::File(path.to_owned(), mime))
        }
        Err(error) if text_input_error(&error) => {
            if content.is_empty() || content.len() > 16 * 1024 {
                return Err("text must contain 1 to 16384 bytes".into());
            }
            Ok(Input::Text)
        }
        Err(error) => Err(format!("cannot inspect {}: {error}", path.display()).into()),
    }
}

fn text_input_error(error: &std::io::Error) -> bool {
    if matches!(
        error.kind(),
        std::io::ErrorKind::NotFound | std::io::ErrorKind::InvalidInput
    ) {
        return true;
    }
    #[cfg(unix)]
    if error.raw_os_error() == Some(libc::ENAMETOOLONG) {
        return true;
    }
    false
}

pub(super) fn kind_for_mime(mime: &str) -> BoxKind {
    if mime.starts_with("image/") {
        BoxKind::Image
    } else if mime.starts_with("video/") {
        BoxKind::Video
    } else {
        BoxKind::File
    }
}

pub(super) fn mime_for_path(path: &Path) -> String {
    let ext = path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_lowercase();
    match ext.as_str() {
        "mp4" | "m4v" => "video/mp4".into(),
        "mov" => "video/quicktime".into(),
        "webm" => "video/webm".into(),
        "avi" => "video/x-msvideo".into(),
        "heic" => "image/heic".into(),
        "heif" => "image/heif".into(),
        "avif" => "image/avif".into(),
        "bmp" => "image/bmp".into(),
        "tif" | "tiff" => "image/tiff".into(),
        _ => crate::client::mime_from_ext(&path.to_string_lossy()),
    }
}
