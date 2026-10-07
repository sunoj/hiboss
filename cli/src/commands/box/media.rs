// Purpose: Save authenticated Box media atomically and reuse complete cached files.
// Exports: save_media, cache_directory, extension; uses HiBossClient and std filesystem I/O.
use crate::{box_types::BoxItem, client::HiBossClient, config::Config};
use std::{
    error::Error,
    fs,
    io::Write,
    path::{Component, Path, PathBuf},
};

struct PartialFile(PathBuf);

impl Drop for PartialFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn component(value: &str) -> Result<(), Box<dyn Error>> {
    let mut components = Path::new(value).components();
    if !matches!(components.next(), Some(Component::Normal(_)))
        || components.next().is_some()
        || value.contains('\\')
    {
        return Err("Box item ID or profile is not a safe filename component".into());
    }
    Ok(())
}

pub(super) fn cache_directory(root: &Path, config: &Config) -> Result<PathBuf, Box<dyn Error>> {
    let profile = config
        .selected_profile
        .as_deref()
        .unwrap_or(&config.default_profile);
    component(profile)?;
    Ok(root.join("hiboss").join("box").join(profile))
}

pub(super) async fn save_media(
    client: &HiBossClient,
    item: &BoxItem,
    config: &Config,
    save: Option<&Path>,
) -> Result<Option<PathBuf>, Box<dyn Error>> {
    if !item.has_media {
        return Ok(None);
    }
    component(&item.id)?;
    let directory = match save {
        Some(path) => path.to_owned(),
        None => cache_directory(
            &dirs::cache_dir().ok_or("cannot find the system cache directory; use --save")?,
            config,
        )?,
    };
    fs::create_dir_all(&directory)
        .map_err(|err| format!("cannot create media directory {}: {err}", directory.display()))?;
    let directory = fs::canonicalize(&directory)?;
    let path = directory.join(format!("{}.{}", item.id, extension(item.media_type.as_deref())));
    if let Ok(metadata) = fs::symlink_metadata(&path) {
        if metadata.is_file()
            && item
                .media_bytes
                .is_some_and(|size| size > 0 && size == metadata.len())
        {
            return Ok(Some(path));
        }
    }
    download(client, item, &path)
        .await
        .map_err(|err| format!("cannot save Box media to {}: {err}", path.display()))?;
    Ok(Some(path))
}

async fn download(client: &HiBossClient, item: &BoxItem, path: &Path) -> Result<(), Box<dyn Error>> {
    let mut response = client.box_media(&item.id).await?;
    if response.status() != reqwest::StatusCode::OK {
        return Err("media download did not return a complete response".into());
    }
    let expected = item.media_bytes.or(response.content_length());
    let temporary =
        PartialFile(path.with_extension(format!("{}.part", crate::client::box_items::fresh_key()?)));
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&temporary.0)?;
    let mut written = 0u64;
    while let Some(chunk) = response.chunk().await? {
        written += chunk.len() as u64;
        if written > 50 * 1024 * 1024 || expected.is_some_and(|size| written > size) {
            return Err("media download exceeds its expected size".into());
        }
        file.write_all(&chunk)?;
    }
    if written == 0 || expected.is_some_and(|size| written != size) {
        return Err("media download is incomplete".into());
    }
    file.sync_all()?;
    drop(file);
    fs::rename(&temporary.0, path)?;
    Ok(())
}

pub(super) fn extension(media_type: Option<&str>) -> &'static str {
    let mime = media_type
        .unwrap_or("")
        .split(';')
        .next()
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    match mime.as_str() {
        "image/png" => "png",
        "image/jpeg" => "jpg",
        "image/gif" => "gif",
        "image/webp" => "webp",
        "image/svg+xml" => "svg",
        "image/heic" => "heic",
        "image/heif" => "heif",
        "image/avif" => "avif",
        "image/bmp" => "bmp",
        "image/tiff" => "tiff",
        "video/mp4" => "mp4",
        "video/quicktime" => "mov",
        "video/webm" => "webm",
        "video/x-msvideo" => "avi",
        "application/pdf" => "pdf",
        "application/json" => "json",
        "text/plain" => "txt",
        "text/html" => "html",
        "text/css" => "css",
        "application/javascript" => "js",
        "application/zip" => "zip",
        "application/x-tar" => "tar",
        "application/gzip" => "gz",
        _ => "bin",
    }
}
