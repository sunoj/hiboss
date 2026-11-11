-- Lets the admin panel list walk the newest panels in order instead of sorting every panel.
CREATE INDEX idx_panels_created ON panels(created_at DESC, panel_id DESC);
-- Lets questionnaire discovery visit open requests only; accepted and withdrawn ones stay.
CREATE INDEX idx_interaction_open ON interaction_requests(created_at, request_id) WHERE state = 'open';
-- Lets the cron expiry sweep visit open messages whose deadline passed, not every past deadline.
CREATE INDEX idx_messages_open_expires ON messages(expires_at, id)
  WHERE expires_at IS NOT NULL AND status IN ('sent', 'delivered', 'read');
