// Download note images into a private, atomic per-user cache.
// Exports save; depends on authenticated note transport and filesystem permissions.
use crate::client::{HiBossClient, notes::NoteImage};
use std::{
    error::Error,
    fs,
    io::Write,
    path::{Component, Path, PathBuf},
};

struct Partial(PathBuf);
impl Drop for Partial {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn directory(path: &Path) -> Result<(), Box<dyn Error>> {
    let mut builder = fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        builder.mode(0o700);
    }
    match builder.create(path) {
        Ok(()) => (),
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => (),
        Err(e) => return Err(e.into()),
    }
    if !fs::symlink_metadata(path)?.is_dir() {
        return Err("note cache path is not a directory".into());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}

fn cache_path(note: &str, image: &NoteImage) -> Result<PathBuf, Box<dyn Error>> {
    let mut parts = Path::new(note).components();
    if !matches!(parts.next(), Some(Component::Normal(_)))
        || parts.next().is_some()
        || note.contains('\\')
    {
        return Err("unsafe note ID".into());
    }
    let ext = match image.content_type.as_str() {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/heic" => "heic",
        "image/webp" => "webp",
        "image/gif" => "gif",
        _ => return Err("unsupported note image type".into()),
    };
    if image.index > 3 || image.bytes == 0 || image.bytes > 10 * 1024 * 1024 {
        return Err("invalid note image metadata".into());
    }
    let mut path = dirs::cache_dir().ok_or("cannot find user cache directory")?;
    fs::create_dir_all(&path)?;
    for part in ["hiboss", "notes", note] {
        path.push(part);
        directory(&path)?;
    }
    Ok(path.join(format!("{}.{ext}", image.index)))
}

pub(super) async fn save(
    client: &HiBossClient,
    session: &str,
    note: &str,
    image: &NoteImage,
) -> Result<String, Box<dyn Error>> {
    let path = cache_path(note, image)?;
    if let Ok(meta) = fs::symlink_metadata(&path) {
        if meta.is_file() && meta.len() == image.bytes {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
            }
            return Ok(path.to_string_lossy().into_owned());
        }
    }
    download(client, session, note, image, &path).await?;
    Ok(path.to_string_lossy().into_owned())
}

async fn download(
    client: &HiBossClient,
    session: &str,
    note: &str,
    image: &NoteImage,
    path: &Path,
) -> Result<(), Box<dyn Error>> {
    let mut response = client.note_image(session, note, image.index).await?;
    if response.status() != reqwest::StatusCode::OK {
        return Err("image download did not return a complete response".into());
    }
    let partial =
        Partial(path.with_extension(format!("{}.part", crate::client::box_items::fresh_key()?)));
    let mut options = fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&partial.0)?;
    let mut written = 0;
    while let Some(chunk) = response.chunk().await? {
        written += chunk.len() as u64;
        if written > image.bytes {
            return Err("image exceeds expected size".into());
        }
        file.write_all(&chunk)?;
    }
    if written != image.bytes {
        return Err("incomplete image download".into());
    }
    file.sync_all()?;
    drop(file);
    fs::rename(&partial.0, &path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notes_reject_unsafe_cache_ids_and_invalid_image_metadata() {
        let mut image = NoteImage {
            index: 0,
            content_type: "image/png".into(),
            bytes: 8,
            path: None,
        };
        for note in ["../other", "/absolute", "a/b", "a\\b", ".", ""] {
            assert!(cache_path(note, &image).is_err());
        }
        image.index = 4;
        assert!(cache_path("safe", &image).is_err());
        image.index = 0;
        image.bytes = 10 * 1024 * 1024 + 1;
        assert!(cache_path("safe", &image).is_err());
        image.bytes = 8;
        image.content_type = "image/svg+xml".into();
        assert!(cache_path("safe", &image).is_err());
    }
}
