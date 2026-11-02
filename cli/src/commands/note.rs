// Read and list boss notes for the current session.
// Exports NoteCommand and run; reads are printed before acknowledgement.
use crate::{client::HiBossClient, session};
use clap::Subcommand;
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
    let session = session::read_session_id().ok_or("No current session; run hiboss hook session-start")?;
    let (all, json, mark) = match command {
        NoteCommand::Read { json } => (false, *json, true),
        NoteCommand::List { all, json } => (*all, *json, false),
    };
    let response = client.session_notes(&session, all).await?;
    let mut stdout = std::io::stdout().lock();
    if json {
        writeln!(stdout, "{}", serde_json::to_string_pretty(&response)?)?;
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
        }
    }
    stdout.flush()?;
    drop(stdout);
    if mark {
        for chunk in response.notes.chunks(50) {
            let ids: Vec<&str> = chunk.iter().map(|note| note.id.as_str()).collect();
            client.read_notes(&session, &ids).await?;
        }
        super::hook_notes::refresh(client, &session).await;
    }
    Ok(())
}
