// Purpose: Render optional JPEG thumbnails with sips (images) or ffmpeg (images and video
// posters) at a given size and byte limit, never upscaling; absent tools mean no thumbnail.
// Exports: Tools, Size, BOX/MESSAGE sizes, for_upload, generate; uses the media command runner.
use crate::commands::progress::progress_media::{run_media_command, temp_path, TempFile, MEDIA_COMMAND_TIMEOUT};
use std::path::{Path, PathBuf};
use std::process::Command;
#[cfg(all(test, unix))]
pub(crate) mod tests;

/// Longest side in pixels and the largest accepted JPEG.
#[derive(Clone, Copy)]
pub(crate) struct Size {
    pub longest_side: u32,
    pub max_bytes: usize,
}

/// Box upload thumbnail.
const BOX: Size = Size { longest_side: 512, max_bytes: 256 * 1024 };
/// Display copy of a message or ask option image.
pub(crate) const MESSAGE: Size = Size { longest_side: 1280, max_bytes: 400 * 1024 };
#[cfg(test)]
const MAX_BYTES: usize = BOX.max_bytes;
/// JPEG quality 0.7, then the single retry at 0.5, as sips percent and ffmpeg -q:v.
const QUALITIES: [(&str, &str); 2] = [("70", "5"), ("50", "9")];

/// Programs used to render thumbnails; tests substitute fakes.
pub(crate) struct Tools {
    pub sips: PathBuf,
    pub ffmpeg: PathBuf,
}

impl Tools {
    pub fn system() -> Self {
        Self {
            sips: "sips".into(),
            ffmpeg: "ffmpeg".into(),
        }
    }
}

#[derive(Clone, Copy)]
enum Tool {
    Sips,
    Ffmpeg,
}

/// Thumbnail bytes for an image or video upload, or None with a `--verbose` note.
pub(super) fn for_upload(path: &Path, mime: &str, tools: &Tools, verbose: bool) -> Option<Vec<u8>> {
    let is_image = mime.starts_with("image/");
    if !is_image && !mime.starts_with("video/") {
        return None;
    }
    let result = generate(path, is_image, tools, BOX).and_then(|bytes| {
        let file_len = std::fs::metadata(path).map(|meta| meta.len()).unwrap_or(u64::MAX);
        let total = file_len.saturating_add(bytes.len() as u64);
        if total > super::input::size_limit(mime) {
            Err("the file and thumbnail together exceed the upload limit".to_owned())
        } else {
            Ok(bytes)
        }
    });
    match result {
        Ok(bytes) => Some(bytes),
        Err(reason) => {
            if verbose {
                eprintln!("Note: uploading without a thumbnail ({reason}); boss clients will add one");
            }
            None
        }
    }
}

/// JPEG bytes within `size`, or the reason none could be made.
pub(crate) fn generate(path: &Path, is_image: bool, tools: &Tools, size: Size) -> Result<Vec<u8>, String> {
    let order: &[Tool] = if is_image { &[Tool::Sips, Tool::Ffmpeg] } else { &[Tool::Ffmpeg] };
    let mut oversize = false;
    for &tool in order {
        for quality in QUALITIES {
            match render(tool, tools, path, quality, size.longest_side) {
                Some(bytes) if bytes.len() <= size.max_bytes => return Ok(bytes),
                Some(_) => oversize = true,
                None => break,
            }
        }
    }
    Err(if oversize {
        format!("it exceeded {} KiB at quality 0.5", size.max_bytes / 1024)
    } else {
        "sips/ffmpeg are unavailable or could not read the file".to_owned()
    })
}

/// One rendering attempt; None when the tool is missing, fails or writes a non-JPEG.
fn render(tool: Tool, tools: &Tools, input: &Path, (percent, qscale): (&str, &str), side: u32) -> Option<Vec<u8>> {
    let output = TempFile(temp_path("hiboss-thumb", "jpg"));
    let mut command = match tool {
        Tool::Sips => {
            // sips -Z enlarges small images, so cap the side at the image's own longest side.
            let side = sips_longest_side(tools, input).map_or(side, |own| own.min(side)).to_string();
            let mut command = Command::new(&tools.sips);
            command.args(["-s", "format", "jpeg", "-s", "formatOptions", percent, "-Z", &side]);
            command.arg(input).arg("--out").arg(&output.0);
            command
        }
        Tool::Ffmpeg => {
            let filter = format!("scale='min({side},iw)':'min({side},ih)':force_original_aspect_ratio=decrease");
            let mut command = Command::new(&tools.ffmpeg);
            command.args(["-y", "-v", "error", "-i"]).arg(input);
            command.args([
                "-frames:v", "1",
                "-vf", filter.as_str(),
                "-q:v", qscale, "-f", "image2", "-c:v", "mjpeg",
            ]);
            command.arg(&output.0);
            command
        }
    };
    let label = match tool {
        Tool::Sips => "sips thumbnail",
        Tool::Ffmpeg => "ffmpeg thumbnail",
    };
    let finished = run_media_command(&mut command, label, MEDIA_COMMAND_TIMEOUT)?;
    if !finished.status.success() {
        return None;
    }
    let bytes = std::fs::read(&output.0).ok()?;
    bytes.starts_with(&[0xFF, 0xD8, 0xFF]).then_some(bytes)
}

/// The image's longest side as `sips -g` reports it, or None when it cannot be read.
fn sips_longest_side(tools: &Tools, input: &Path) -> Option<u32> {
    let mut command = Command::new(&tools.sips);
    command.args(["-g", "pixelWidth", "-g", "pixelHeight"]).arg(input);
    let finished = run_media_command(&mut command, "sips size probe", MEDIA_COMMAND_TIMEOUT)?;
    let text = String::from_utf8_lossy(&finished.stdout);
    let value = |key: &str| text.lines().find_map(|line| line.trim().strip_prefix(key)?.trim().parse::<u32>().ok());
    let longest = value("pixelWidth:")?.max(value("pixelHeight:")?);
    (finished.status.success() && longest > 0).then_some(longest)
}
