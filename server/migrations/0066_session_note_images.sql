-- Images are owned and authorized through their session note.
-- Object bytes live in the private notes/ namespace of ATTACHMENTS.
CREATE TABLE session_note_images (
  note_id TEXT NOT NULL REFERENCES session_notes(id),
  idx INTEGER NOT NULL,
  content_type TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  r2_key TEXT NOT NULL,
  PRIMARY KEY (note_id, idx)
);
