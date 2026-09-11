-- Durable questionnaire heads, immutable revisions, answers, and pull-delivery receipts.
-- Used by panel requests; submission and lifecycle writers update these atomically in D1.
CREATE TABLE interaction_requests (
  request_id TEXT PRIMARY KEY,
  panel_id TEXT NOT NULL REFERENCES panels(panel_id),
  revision INTEGER NOT NULL CHECK (revision > 0),
  state TEXT NOT NULL CHECK (state IN ('open', 'accepted', 'withdrawn')),
  expires_at TEXT,
  blocking INTEGER NOT NULL CHECK (blocking IN (0, 1)),
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  submission_id TEXT UNIQUE,
  withdrawal_reason TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(panel_id, idempotency_key)
);
CREATE INDEX idx_interaction_panel ON interaction_requests(panel_id, created_at, request_id);
CREATE TABLE interaction_revisions (
  request_id TEXT NOT NULL REFERENCES interaction_requests(request_id),
  revision INTEGER NOT NULL,
  definition_json TEXT NOT NULL CHECK (json_valid(definition_json)),
  PRIMARY KEY(request_id, revision)
);
CREATE TABLE interaction_submissions (
  submission_id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL UNIQUE REFERENCES interaction_requests(request_id),
  revision INTEGER NOT NULL,
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  payload_hash TEXT NOT NULL,
  answers_json TEXT NOT NULL CHECK (json_valid(answers_json)),
  provenance_json TEXT NOT NULL CHECK (json_valid(provenance_json)),
  accepted_at TEXT NOT NULL,
  FOREIGN KEY(request_id, revision) REFERENCES interaction_revisions(request_id, revision)
);
CREATE TABLE interaction_deliveries (
  submission_id TEXT PRIMARY KEY REFERENCES interaction_submissions(submission_id),
  acknowledged_at TEXT
);
