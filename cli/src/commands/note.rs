// Read and list boss notes for the current session.
// Exports NoteCommand and run; reads are printed before acknowledgement.
use crate::{client::HiBossClient, session};
use clap::Subcommand;
#[path = "note_images.rs"]
mod note_images;
use std::{error::Error, io::Write};

#[derive(Debug, Subcommand)]
pub enum NoteCommand {
    Read {
        #[arg(long)]
        json: bool,
    },
    List {
        #[arg(long)]
        all: bool,
        #[arg(long)]
        json: bool,
    },
}

pub async fn run(command: &NoteCommand, client: &HiBossClient) -> Result<(), Box<dyn Error>> {
    let session =
        session::read_session_id().ok_or("No current session; run hiboss hook session-start")?;
    let (all, json, mark) = match command {
        NoteCommand::Read { json } => (false, *json, true),
        NoteCommand::List { all, json } => (*all, *json, false),
    };
    let mut response = client.session_notes(&session, all).await?;
    let mut complete = Vec::new();
    for note in &mut response.notes {
        let mut success = true;
        for image in &mut note.images {
            match note_images::save(client, &session, &note.id, image).await {
                Ok(path) => image.path = Some(path),
                Err(error) => {
                    eprintln!("Note {} image {}: {error}", note.id, image.index);
                    success = false;
                }
            }
        }
        if success {
            complete.push(note.id.clone());
        }
    }
    print_notes(&response, all, json)?;
    if mark {
        let ids: Vec<&str> = complete.iter().map(String::as_str).collect();
        for chunk in ids.chunks(50) {
            client.read_notes(&session, chunk).await?;
        }
        super::hook_notes::refresh(client, &session).await;
    }
    Ok(())
}

fn print_notes(
    response: &crate::client::notes::NotesResponse,
    all: bool,
    json: bool,
) -> Result<(), Box<dyn Error>> {
    let mut stdout = std::io::stdout().lock();
    if json {
        writeln!(stdout, "{}", serde_json::to_string_pretty(response)?)?;
    } else if response.notes.is_empty() {
        writeln!(
            stdout,
            "No {}notes for this session.",
            if all { "" } else { "pending " }
        )?;
    } else {
        for note in &response.notes {
            writeln!(
                stdout,
                "{} · {} · {} [{}]\n{}\n",
                note.boss_name, note.created_at, note.id, note.status, note.body
            )?;
            for (position, image) in note.images.iter().enumerate() {
                if let Some(path) = &image.path {
                    writeln!(
                        stdout,
                        "  image {}/{}: {} ({}, {} KB) — open it to view",
                        position + 1,
                        note.images.len(),
                        path,
                        image.content_type,
                        image.bytes.div_ceil(1024)
                    )?;
                }
            }
        }
    }
    stdout.flush()?;
    drop(stdout);
    Ok(())
}
