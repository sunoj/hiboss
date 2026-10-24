// Purpose: Make the optional Box upload thumbnail (JPEG, longest side 512 px, ≤ 256 KiB)
// with sips (images) or ffmpeg (images and video posters); absent tools mean no thumbnail.
// Exports: Tools, for_upload; depends on the progress media command runner.
use crate::commands::progress::progress_media::{run_media_command, temp_path, TempFile, MEDIA_COMMAND_TIMEOUT};
use std::path::{Path, PathBuf};
use std::process::Command;
#[cfg(all(test, unix))]
mod tests;

const MAX_BYTES: usize = 256 * 1024;
const LONGEST_SIDE: &str = "512";
/// JPEG quality 0.7, then the single retry at 0.5, as sips percent and ffmpeg -q:v.
const QUALITIES: [(&str, &str); 2] = [("70", "5"), ("50", "9")];

/// Programs used to render thumbnails; tests substitute fakes.
pub(super) struct Tools {
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
    let result = generate(path, is_image, tools).and_then(|bytes| {
        let file_len = std::fs::metadata(path).map(|meta| meta.len()).unwrap_or(u64::MAX);
        let total = file_len.saturating_add(bytes.len() as u64);
        if total > super::input::size_limit(mime) {
            Err("the file and thumbnail together exceed the upload limit")
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

fn generate(path: &Path, is_image: bool, tools: &Tools) -> Result<Vec<u8>, &'static str> {
    let order: &[Tool] = if is_image { &[Tool::Sips, Tool::Ffmpeg] } else { &[Tool::Ffmpeg] };
    let mut oversize = false;
    for &tool in order {
        for quality in QUALITIES {
            match render(tool, tools, path, quality) {
                Some(bytes) if bytes.len() <= MAX_BYTES => return Ok(bytes),
                Some(_) => oversize = true,
                None => break,
            }
        }
    }
    Err(if oversize {
        "it exceeded 256 KiB at quality 0.5"
    } else {
        "sips/ffmpeg are unavailable or could not read the file"
    })
}

/// One rendering attempt; None when the tool is missing, fails or writes a non-JPEG.
fn render(tool: Tool, tools: &Tools, input: &Path, (percent, qscale): (&str, &str)) -> Option<Vec<u8>> {
    let output = TempFile(temp_path("hiboss-thumb", "jpg"));
    let mut command = match tool {
        Tool::Sips => {
            let mut command = Command::new(&tools.sips);
            command.args(["-s", "format", "jpeg", "-s", "formatOptions", percent, "-Z", LONGEST_SIDE]);
            command.arg(input).arg("--out").arg(&output.0);
            command
        }
        Tool::Ffmpeg => {
            let mut command = Command::new(&tools.ffmpeg);
            command.args(["-y", "-v", "error", "-i"]).arg(input);
            command.args([
                "-frames:v", "1",
                "-vf", "scale=512:512:force_original_aspect_ratio=decrease",
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
