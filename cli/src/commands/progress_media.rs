// Purpose: Local media probing, GIF conversion, and video poster extraction helpers.
// Exports: TempFile, probe_image_dims, probe_video_meta, convert_gif_to_mp4,
//          extract_video_poster, mime_for_path.
// Dependencies: std::process::Command, std::path::PathBuf, serde_json.

use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, ExitStatus, Stdio};
use std::time::{Duration, Instant};

const MEDIA_COMMAND_TIMEOUT: Duration = Duration::from_secs(30);

struct CommandOutput {
    status: ExitStatus,
    stdout: Vec<u8>,
}

/// RAII guard that deletes a temporary file on drop.
pub(super) struct TempFile(pub PathBuf);

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// Probe image pixel dimensions: tries ffprobe first, then sips (macOS).
/// Returns None when neither tool is available or the file cannot be probed.
pub(super) fn probe_image_dims(path: &str) -> Option<(u32, u32)> {
    probe_dims_ffprobe(path).or_else(|| probe_dims_sips(path))
}

fn probe_dims_ffprobe(path: &str) -> Option<(u32, u32)> {
    let out = run_media_command(
        Command::new("ffprobe")
            .args(["-v", "quiet", "-print_format", "json", "-show_streams", path]),
        "ffprobe",
        MEDIA_COMMAND_TIMEOUT,
    )?;
    if !out.status.success() {
        return None;
    }
    let json: serde_json::Value = serde_json::from_slice(&out.stdout).ok()?;
    json["streams"].as_array()?.iter().find_map(|s| {
        let w = s["width"].as_u64()? as u32;
        let h = s["height"].as_u64()? as u32;
        (w > 0 && h > 0).then_some((w, h))
    })
}

fn probe_dims_sips(path: &str) -> Option<(u32, u32)> {
    let out = run_media_command(
        Command::new("sips").args(["-g", "pixelWidth", "-g", "pixelHeight", path]),
        "sips",
        MEDIA_COMMAND_TIMEOUT,
    )?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut w: Option<u32> = None;
    let mut h: Option<u32> = None;
    for line in text.lines() {
        let line = line.trim();
        if let Some(v) = line.strip_prefix("pixelWidth: ") {
            w = v.trim().parse().ok();
        } else if let Some(v) = line.strip_prefix("pixelHeight: ") {
            h = v.trim().parse().ok();
        }
    }
    w.zip(h)
}

/// Probe video dimensions and duration_ms using ffprobe.
/// Returns (dims, duration_ms); either may be None when ffprobe is unavailable.
pub(super) fn probe_video_meta(path: &str) -> (Option<(u32, u32)>, Option<u64>) {
    let out = match run_media_command(
        Command::new("ffprobe").args([
            "-v", "quiet", "-print_format", "json",
            "-show_streams", "-show_format", path,
        ]),
        "ffprobe",
        MEDIA_COMMAND_TIMEOUT,
    ) {
        Some(o) if o.status.success() => o,
        _ => return (None, None),
    };
    let json: serde_json::Value = match serde_json::from_slice(&out.stdout) {
        Ok(v) => v,
        Err(_) => return (None, None),
    };
    let dims = json["streams"].as_array().and_then(|streams| {
        streams.iter().find_map(|s| {
            let w = s["width"].as_u64()? as u32;
            let h = s["height"].as_u64()? as u32;
            (w > 0 && h > 0).then_some((w, h))
        })
    });
    let duration_ms = json["format"]["duration"]
        .as_str()
        .and_then(|s| s.parse::<f64>().ok())
        .map(|secs| (secs * 1000.0) as u64);
    (dims, duration_ms)
}

/// Convert a GIF to a muted looping MP4 using ffmpeg (yuv420p, +faststart).
/// Returns None — without panicking — when ffmpeg is absent or conversion fails.
pub(super) fn convert_gif_to_mp4(path: &str) -> Option<TempFile> {
    let out = temp_path("hiboss-gif", "mp4");
    let result = run_media_command(
        Command::new("ffmpeg").args([
            "-y", "-i", path,
            "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-an", "-movflags", "+faststart",
            out.to_str()?,
        ]),
        "ffmpeg GIF conversion",
        MEDIA_COMMAND_TIMEOUT,
    );
    if result.is_some_and(|output| output.status.success()) {
        Some(TempFile(out))
    } else {
        let _ = std::fs::remove_file(&out);
        None
    }
}

/// Extract the first video frame as JPEG using ffmpeg.
/// Returns None — without panicking — when ffmpeg is absent or extraction fails.
pub(super) fn extract_video_poster(path: &str) -> Option<TempFile> {
    let out = temp_path("hiboss-poster", "jpg");
    let result = run_media_command(
        Command::new("ffmpeg").args(["-y", "-i", path, "-vframes", "1", "-q:v", "2", out.to_str()?]),
        "ffmpeg poster extraction",
        MEDIA_COMMAND_TIMEOUT,
    );
    if result.is_some_and(|output| output.status.success()) {
        Some(TempFile(out))
    } else {
        let _ = std::fs::remove_file(&out);
        None
    }
}

fn run_media_command(command: &mut Command, label: &str, timeout: Duration) -> Option<CommandOutput> {
    command.stdout(Stdio::piped()).stderr(Stdio::null());
    let mut child = command.spawn().ok()?;
    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let mut stdout = Vec::new();
                if let Some(mut pipe) = child.stdout.take() {
                    let _ = pipe.read_to_end(&mut stdout);
                }
                return Some(CommandOutput { status, stdout });
            }
            Ok(None) if started.elapsed() >= timeout => {
                let _ = child.kill();
                let _ = child.wait();
                eprintln!(
                    "Warning: {label} timed out after {} seconds; skipping media enhancement",
                    timeout.as_secs()
                );
                return None;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(50)),
            Err(_) => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    }
}

/// Infer a MIME type from a file path's extension.
pub(super) fn mime_for_path(path: &str) -> &'static str {
    match path.rsplit('.').next().unwrap_or("").to_lowercase().as_str() {
        "png"        => "image/png",
        "jpg"|"jpeg" => "image/jpeg",
        "gif"        => "image/gif",
        "webp"       => "image/webp",
        "mp4"        => "video/mp4",
        "mov"        => "video/quicktime",
        _            => "application/octet-stream",
    }
}

fn temp_path(prefix: &str, ext: &str) -> PathBuf {
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    std::env::temp_dir().join(format!("{}-{}-{}.{}", prefix, ts, std::process::id(), ext))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mime_for_path_png() {
        assert_eq!(mime_for_path("screenshot.png"), "image/png");
    }

    #[test]
    fn mime_for_path_mp4() {
        assert_eq!(mime_for_path("clip.mp4"), "video/mp4");
    }

    #[test]
    fn mime_for_path_case_insensitive() {
        assert_eq!(mime_for_path("photo.JPG"), "image/jpeg");
    }

    #[test]
    fn mime_for_path_unknown() {
        assert_eq!(mime_for_path("file.xyz"), "application/octet-stream");
    }

    #[test]
    fn probe_image_dims_none_for_nonexistent() {
        assert!(probe_image_dims("/nonexistent/img.png").is_none());
    }

    #[test]
    fn probe_video_meta_none_for_nonexistent() {
        let (dims, dur) = probe_video_meta("/nonexistent/clip.mp4");
        assert!(dims.is_none());
        assert!(dur.is_none());
    }

    #[test]
    fn convert_gif_degrades_gracefully_on_bad_input() {
        // ffmpeg absent → None; ffmpeg present but file missing → None. No panic.
        let result = convert_gif_to_mp4("/nonexistent/file.gif");
        let _ = result;
    }

    #[test]
    fn extract_poster_degrades_gracefully_on_bad_input() {
        let result = extract_video_poster("/nonexistent/clip.mp4");
        let _ = result;
    }

    #[test]
    fn temp_path_is_in_temp_dir() {
        let p = temp_path("test", "mp4");
        assert_eq!(p.parent(), Some(std::env::temp_dir().as_path()));
    }

    #[cfg(unix)]
    #[test]
    fn media_command_kills_a_timed_out_child() {
        let result = run_media_command(
            Command::new("sh").args(["-c", "while :; do :; done"]),
            "test media command",
            Duration::from_millis(20),
        );
        assert!(result.is_none());
    }
}
