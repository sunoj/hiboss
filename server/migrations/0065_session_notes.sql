-- Session-scoped boss notes and retry keys.
-- Notes have no message delivery or inbox side effects.
CREATE TABLE session_notes (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id),
  agent_id TEXT NOT NULL,
  boss_id TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'read')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  read_at TEXT
);
CREATE INDEX idx_session_notes_status ON session_notes(session_id, status);
CREATE TABLE session_note_keys (
  boss_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  key TEXT NOT NULL,
  note_id TEXT NOT NULL REFERENCES session_notes(id),
  PRIMARY KEY (boss_id, session_id, key)
);
