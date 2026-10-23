-- Live Activity push tokens for direct-mode asks; the server ends each activity when its ask closes.
-- One row per boss device and ask; deleting the device or the message deletes its rows.
CREATE TABLE live_activity_tokens (
  device_id TEXT NOT NULL REFERENCES boss_devices(id) ON DELETE CASCADE,
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  activity_token TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (device_id, message_id)
);
CREATE INDEX idx_live_activity_tokens_message ON live_activity_tokens(message_id);
CREATE INDEX idx_live_activity_tokens_updated ON live_activity_tokens(updated_at);
