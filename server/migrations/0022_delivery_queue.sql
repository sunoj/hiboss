CREATE TABLE IF NOT EXISTS delivery_queue (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  message_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  channel TEXT NOT NULL,
  config TEXT NOT NULL,
  scheduled_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'delivered', 'failed')),
  error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (message_id) REFERENCES messages(id)
);

CREATE INDEX idx_delivery_queue_pending ON delivery_queue(status, scheduled_at) WHERE status = 'pending';
