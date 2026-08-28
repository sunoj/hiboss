PRAGMA foreign_keys = ON;
CREATE TABLE messages (id TEXT PRIMARY KEY);
CREATE TABLE session_events (message_id TEXT REFERENCES messages(id));
INSERT INTO messages VALUES ('1');
INSERT INTO session_events VALUES ('1');

BEGIN TRANSACTION;
PRAGMA defer_foreign_keys = on;
CREATE TABLE messages_new (id TEXT PRIMARY KEY);
DROP TABLE messages;
COMMIT;
