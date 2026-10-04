-- Sign in with iPhone: a signed-out Mac opens a request and shows it as a QR code; a
-- signed-in boss approves it on the iPhone, which then displays a 6-digit code; the Mac
-- sends that code to collect its own boss token. Only hashes of the poll token and the
-- code are stored. Rows expire after ten minutes and the cron sweep deletes them.
-- origin_key is a hash of the opener's IP address, used only to cap open requests per network.
CREATE TABLE signin_requests (
  id TEXT PRIMARY KEY,
  poll_token_hash TEXT NOT NULL UNIQUE,
  device_label TEXT NOT NULL,
  origin TEXT,
  origin_key TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
  boss_id TEXT REFERENCES bosses(id) ON DELETE CASCADE,
  approved_by_token_id TEXT REFERENCES boss_tokens(id) ON DELETE SET NULL,
  code_hash TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  issued_token_id TEXT REFERENCES boss_tokens(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX idx_signin_requests_expires ON signin_requests(expires_at);
CREATE INDEX idx_signin_requests_origin ON signin_requests(origin_key) WHERE origin_key IS NOT NULL;
