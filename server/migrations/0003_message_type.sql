-- v0.5.1: Add type field for structured message types.
--
-- This was once neutered to `SELECT 1` because the column had already been added
-- out-of-band in production. That left the migration chain unable to build a fresh
-- database: 0011 recreates `messages` with `SELECT ... type ... FROM messages`, which
-- fails with `no such column: type` on any database that only ever ran the migrations.
--
-- Restored deliberately. Production recorded 0003 as applied long ago and will never
-- re-run it, so this only affects databases built from scratch — the case that was broken.
ALTER TABLE messages ADD COLUMN type TEXT DEFAULT 'text';
