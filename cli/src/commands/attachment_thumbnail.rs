// Purpose: Upload a local message attachment and, for images, a 1280 px JPEG display copy
// beside it; a missing tool or failed upload leaves the thumbnail out (noted under --verbose).
// Exports: Uploaded, upload_with_thumbnail; depends on the Box thumbnail renderer and client.
use super::box_cmd::thumbnail::{generate, Tools, MESSAGE};
use crate::client::{mime_from_ext, HiBossClient};
use std::{error::Error, path::Path};

/// Attachment URLs for one local file.
pub(crate) struct Uploaded {
    pub filename: String,
    pub url: String,
    pub thumbnail_url: Option<String>,
}

/// Upload `path`, then its display copy when it is an image and one can be rendered.
pub(crate) async fn upload_with_thumbnail(
    client: &HiBossClient,
    path: &str,
    tools: &Tools,
    verbose: bool,
) -> Result<Uploaded, Box<dyn Error>> {
    let upload = client.upload_file(path).await?;
    let thumbnail_url = match thumbnail_bytes(Path::new(path), tools) {
        None => None,
        Some(Err(reason)) => note(verbose, &reason),
        Some(Ok(bytes)) => match client.upload_bytes("thumbnail.jpg".to_owned(), "image/jpeg", bytes).await {
            Ok(thumbnail) => Some(thumbnail.url),
            Err(error) => note(verbose, &format!("its upload failed: {error}")),
        },
    };
    Ok(Uploaded { filename: upload.filename, url: upload.url, thumbnail_url })
}

fn thumbnail_bytes(path: &Path, tools: &Tools) -> Option<Result<Vec<u8>, String>> {
    let image = mime_from_ext(&path.to_string_lossy()).starts_with("image/");
    image.then(|| generate(path, true, tools, MESSAGE))
}

fn note(verbose: bool, reason: &str) -> Option<String> {
    if verbose {
        eprintln!("Note: attaching without a thumbnail ({reason}); clients will show the original");
    }
    None
}

#[cfg(all(test, unix))]
#[path = "attachment_thumbnail_tests.rs"]
mod tests;
