-- Link ordinary agent messages to session notes.
-- Message creation and delivery remain in the send pipeline.
CREATE TABLE session_note_replies (
  note_id TEXT NOT NULL REFERENCES session_notes(id),
  message_id TEXT NOT NULL REFERENCES messages(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (note_id, message_id)
);
CREATE INDEX idx_session_note_replies_message ON session_note_replies(message_id);
