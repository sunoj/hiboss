PRAGMA foreign_keys = ON;
CREATE TABLE messages (id TEXT PRIMARY KEY);
CREATE TABLE session_events (message_id TEXT REFERENCES messages(id));

BEGIN TRANSACTION;
PRAGMA defer_foreign_keys = on;
CREATE TABLE messages_new (id TEXT PRIMARY KEY);
DROP TABLE messages;
ALTER TABLE messages_new RENAME TO messages;
COMMIT;
