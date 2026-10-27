-- Documented SQLite objects; authoritative definitions are in migrations/.
-- Render with sh scripts/check-schema.sh --emit; this template is not executable SQL.

-- Agent authentication

-- api_keys = agents. Legacy key_hash is retained read-only.
CREATE TABLE IF NOT EXISTS "api_keys";

-- Devices group the per-runtime agent profiles enrolled from one machine.
CREATE TABLE devices;

CREATE TABLE device_invites;

CREATE INDEX idx_device_invites_inviter;

CREATE INDEX idx_api_keys_device;

-- Independently revocable agent credentials; public inventory never returns hashes.
CREATE TABLE agent_keys;
CREATE INDEX idx_agent_keys_agent;
CREATE INDEX idx_agent_keys_minted_by;

-- Messaging and channel delivery

-- Messages between agents, bosses, and peer agents
CREATE TABLE IF NOT EXISTS messages;

CREATE INDEX IF NOT EXISTS idx_messages_agent;
CREATE INDEX IF NOT EXISTS idx_messages_status;
CREATE INDEX IF NOT EXISTS idx_messages_reply;
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_idempotency;
CREATE INDEX IF NOT EXISTS idx_messages_session;
CREATE INDEX IF NOT EXISTS idx_messages_target;
CREATE INDEX IF NOT EXISTS idx_messages_target_session;
CREATE INDEX IF NOT EXISTS idx_messages_expires_at;
CREATE INDEX IF NOT EXISTS idx_messages_agent_expires;

-- Timestamp range reads and automatic timestamps for message updates.
CREATE INDEX idx_messages_agent_updated;
CREATE TRIGGER messages_updated_at BEGIN SELECT 1; END;

-- Deferred channel deliveries blocked by boss quiet hours
CREATE TABLE IF NOT EXISTS delivery_queue;

CREATE INDEX IF NOT EXISTS idx_delivery_queue_pending;

-- Channel configurations (per agent)
CREATE TABLE IF NOT EXISTS channel_configs;

-- Routing rules: regex patterns route incoming boss messages to agents
CREATE TABLE IF NOT EXISTS routing_rules;

CREATE INDEX IF NOT EXISTS idx_routing_rules_channel;

-- Agent groups

-- Agent groups for broadcast messaging
CREATE TABLE IF NOT EXISTS agent_groups;

-- Membership of agents in broadcast groups
CREATE TABLE IF NOT EXISTS agent_group_members;

-- Boss identity and access

-- Boss identities and preferences
CREATE TABLE IF NOT EXISTS bosses;

CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_telegram;
CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_discord;
CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_agent;

-- Installed boss clients
CREATE TABLE boss_clients;
CREATE INDEX idx_boss_clients_boss;

-- Independent bearer tokens and short-lived QR pairing codes for bosses
CREATE TABLE IF NOT EXISTS boss_tokens;
CREATE INDEX idx_boss_tokens_client;

CREATE INDEX IF NOT EXISTS idx_boss_tokens_boss;

-- Optional device-held signing keys. A token with a live key must sign messages.
CREATE TABLE IF NOT EXISTS boss_signing_keys;
CREATE INDEX idx_boss_signing_keys_client;

CREATE INDEX IF NOT EXISTS idx_boss_signing_keys_boss;

-- P-256 message-signing keys bound to agent credentials
CREATE TABLE IF NOT EXISTS agent_signing_keys;

CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_signing_keys_live_credential;
CREATE INDEX IF NOT EXISTS idx_agent_signing_keys_agent;

-- One-time codes for enrolling boss clients
CREATE TABLE IF NOT EXISTS boss_pairing_codes;

CREATE INDEX IF NOT EXISTS idx_boss_pairing_codes_expiry;

-- Sign in with iPhone: a signed-out Mac's request, approved on a signed-in iPhone,
-- completed with the 6-digit code the iPhone displays. Hashes only; ten-minute life.
CREATE TABLE IF NOT EXISTS signin_requests;
CREATE INDEX IF NOT EXISTS idx_signin_requests_expires;
CREATE INDEX IF NOT EXISTS idx_signin_requests_origin;

-- Boss-agent access control
CREATE TABLE IF NOT EXISTS boss_agent_access;

-- Boss iOS devices for APNs delivery
CREATE TABLE IF NOT EXISTS boss_devices;
CREATE INDEX idx_boss_devices_client;
CREATE INDEX idx_boss_devices_token;

-- Relay capabilities are unique per registered installation.
CREATE UNIQUE INDEX idx_boss_devices_relay_handle;

CREATE INDEX IF NOT EXISTS idx_boss_devices_boss;

-- Live Activity push tokens per boss device and ask, ended when the ask closes (direct mode).
CREATE TABLE live_activity_tokens;
CREATE INDEX idx_live_activity_tokens_message;
CREATE INDEX idx_live_activity_tokens_updated;

-- Audit history

-- Audit log
CREATE TABLE IF NOT EXISTS audit_log;

CREATE INDEX IF NOT EXISTS idx_audit_log_actor;
CREATE INDEX IF NOT EXISTS idx_audit_log_action;

-- Session registration and onboarding

-- Sessions: ephemeral workspace registrations
CREATE TABLE IF NOT EXISTS sessions;

CREATE INDEX IF NOT EXISTS idx_sessions_agent;
CREATE INDEX IF NOT EXISTS idx_sessions_discord_thread;
CREATE INDEX IF NOT EXISTS idx_sessions_telegram_topic;

-- Join requests: device onboarding
CREATE TABLE IF NOT EXISTS join_requests;


CREATE INDEX IF NOT EXISTS idx_join_requests_status;

-- Progress feed

-- Progress feed posts: deliberately separate from messages and delivery.
CREATE TABLE IF NOT EXISTS progress_posts;

CREATE INDEX IF NOT EXISTS idx_progress_created;
CREATE INDEX IF NOT EXISTS idx_progress_project;
CREATE INDEX IF NOT EXISTS idx_progress_agent;

-- Boss likes on progress feed posts
CREATE TABLE IF NOT EXISTS progress_likes;

CREATE INDEX IF NOT EXISTS idx_progress_likes_post;

-- Session history

-- Append-only per-session event log for history and resumable SSE streams.
CREATE TABLE IF NOT EXISTS session_events;

CREATE INDEX IF NOT EXISTS idx_session_events_cursor;

-- Live panels

-- Panel ownership, current metadata, lifecycle defaults, and durable final state
CREATE TABLE panels;

CREATE INDEX idx_panels_agent_created;
CREATE INDEX idx_panels_boss_created;

-- Immutable panel definition revisions and initial state
CREATE TABLE panel_definitions;

-- Boss-owned panel placement preferences
CREATE TABLE panel_preferences;

-- Immutable idempotency receipts for panel operations
CREATE TABLE panel_operations;

-- Durable panel events awaiting relay delivery
CREATE TABLE panel_outbox;

-- Panel questionnaires

-- Durable questionnaire heads and submission state
CREATE TABLE interaction_requests;
CREATE INDEX idx_interaction_panel;

-- Immutable questionnaire definitions by revision
CREATE TABLE interaction_revisions;

-- Accepted answers and provenance bound to an exact questionnaire revision
CREATE TABLE interaction_submissions;

-- Pull-delivery acknowledgement receipts for accepted answers
CREATE TABLE interaction_deliveries;

-- Add boss-owned destinations and per-message delivery state without touching messages.
-- Backfill legacy credentials, accessible chats, session routes, and native clients.
CREATE TABLE channel_providers;

CREATE UNIQUE INDEX idx_channel_providers_effective_credential;
CREATE TABLE boss_destinations;
CREATE INDEX idx_boss_destinations_boss;
CREATE TABLE destination_routes;
CREATE UNIQUE INDEX idx_destination_routes_scope;
CREATE TABLE inbound_routes;
CREATE TABLE message_deliveries;
CREATE INDEX idx_message_deliveries_message;
CREATE INDEX idx_message_deliveries_retry;

CREATE UNIQUE INDEX idx_message_deliveries_target;
CREATE INDEX idx_message_deliveries_merged;
CREATE TABLE boss_external_accounts;
CREATE INDEX idx_boss_external_accounts_boss;

-- Project identities and profiles retain legacy text columns.
CREATE TABLE projects;
CREATE TABLE project_aliases;
CREATE INDEX idx_project_aliases_project;

CREATE UNIQUE INDEX idx_api_keys_name;
CREATE INDEX idx_sessions_project;
-- A dispatched session points at the same-device session that dispatched it.
CREATE INDEX idx_sessions_parent;
CREATE INDEX idx_sessions_project_nickname;
CREATE INDEX idx_progress_project_id;
CREATE INDEX idx_destination_routes_project;

-- Boss-owned reference items, retry records and full-text search.
-- Search triggers index only live items and follow metadata edits and deletion.
CREATE TABLE box_items;
CREATE INDEX idx_box_items_boss_created;
CREATE TABLE box_idempotency;
CREATE VIRTUAL TABLE box_items_fts;
CREATE TRIGGER box_items_fts_insert BEGIN SELECT 1; END;
CREATE TRIGGER box_items_fts_update BEGIN SELECT 1; END;
CREATE TRIGGER box_items_fts_delete BEGIN SELECT 1; END;

-- Bound each accessible agent's ordered page, including same-second messages.
-- Keep the status index for selective filters and avoid indexing session heartbeats.
CREATE INDEX idx_messages_agent_page;
CREATE INDEX idx_messages_boss_page;
CREATE TABLE box_agent_idempotency;

-- Boss-owned collections with live item summaries and per-item like timestamps.
-- Memberships survive soft deletion and are removed by physical deletion.
CREATE INDEX idx_box_items_liked;
CREATE TABLE box_collections;
CREATE UNIQUE INDEX idx_box_collections_name;
CREATE TABLE box_collection_items;
CREATE INDEX idx_box_collection_items_item;

-- Revocable public Box capabilities; only token hashes are stored.
-- Physical item deletion removes its shares.
CREATE TABLE box_shares;
CREATE INDEX idx_box_shares_item;
