// Media preparation for progress posting.
// Exports upload and item helpers; depends on progress arguments, media tools and client.
use super::*;

pub(super) async fn collect_media(args: &PostArgs, client: &HiBossClient) -> Result<Vec<ProgressMediaItem>, Box<dyn Error>> {
    let mut media: Vec<ProgressMediaItem> = Vec::new();
    let mut alt_idx = 0usize;
    for path in &args.image {
        let alt = args.alt.get(alt_idx).cloned();
        alt_idx += 1;
        media.push(process_image(path, alt, client).await?);
    }
    for path in &args.video {
        let alt = args.alt.get(alt_idx).cloned();
        alt_idx += 1;
        media.push(process_video(path, alt, client).await?);
    }
    for url in &args.url {
        let alt = args.alt.get(alt_idx).cloned();
        alt_idx += 1;
        media.push(url_media_item(url, alt));
    }
    Ok(media)
}

async fn process_image(
    path: &str,
    alt: Option<String>,
    client: &HiBossClient,
) -> Result<ProgressMediaItem, Box<dyn Error>> {
    if path.to_lowercase().ends_with(".gif") {
        if let Some(tmp) = progress_media::convert_gif_to_mp4(path) {
            let mp4 = tmp.0.to_str().ok_or("temp path is not valid UTF-8")?.to_owned();
            let (dims, dur) = progress_media::probe_video_meta(&mp4);
            let up = client.upload_raw_binary(&mp4, "clip.mp4").await?;
            return Ok(make_item(up.url, "video", "video/mp4", up.size, dims, dur, None, alt));
        }
        eprintln!("Warning: GIF conversion unavailable; uploading GIF as-is (iOS shows a still frame)");
    }
    let dims = progress_media::probe_image_dims(path);
    let up = client.upload_file(path).await?;
    Ok(make_item(up.url, "image", &up.content_type, up.size, dims, None, None, alt))
}

async fn process_video(
    path: &str,
    alt: Option<String>,
    client: &HiBossClient,
) -> Result<ProgressMediaItem, Box<dyn Error>> {
    let (dims, dur) = progress_media::probe_video_meta(path);
    let poster_url = match progress_media::extract_video_poster(path) {
        Some(tmp) => {
            let p = tmp.0.to_str().ok_or("poster path is not valid UTF-8")?.to_owned();
            let result = client.upload_file(&p).await.ok().map(|u| u.url);
            drop(tmp);
            result
        }
        None => None,
    };
    let fname = std::path::Path::new(path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("video.mp4");
    let up = client.upload_raw_binary(path, fname).await?;
    Ok(make_item(up.url, "video", &up.content_type, up.size, dims, dur, poster_url, alt))
}

pub(super) fn make_item(
    url: String, kind: &str, content_type: &str, size: u64,
    dims: Option<(u32, u32)>, duration_ms: Option<u64>,
    poster_url: Option<String>, alt: Option<String>,
) -> ProgressMediaItem {
    ProgressMediaItem {
        url, kind: kind.into(), content_type: content_type.into(), size,
        width: dims.map(|(w, _)| w), height: dims.map(|(_, h)| h),
        duration_ms, poster_url, alt,
    }
}

pub(super) fn url_media_item(url: &str, alt: Option<String>) -> ProgressMediaItem {
    let kind = if url.contains(".mp4") || url.contains(".mov") { "video" } else { "image" };
    ProgressMediaItem {
        url: url.to_owned(), kind: kind.into(),
        content_type: progress_media::mime_for_path(url).into(),
        size: 0, width: None, height: None, duration_ms: None, poster_url: None, alt,
    }
}
