PRAGMA foreign_keys = OFF;
CREATE TABLE messages (id TEXT PRIMARY KEY);
CREATE TABLE session_events (message_id TEXT REFERENCES messages(id));
INSERT INTO messages VALUES ('1');
INSERT INTO session_events VALUES ('1');

CREATE TABLE messages_with_a2a_status (id TEXT PRIMARY KEY);
INSERT INTO messages_with_a2a_status SELECT * FROM messages;
DROP TABLE messages;
ALTER TABLE messages_with_a2a_status RENAME TO messages;

PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;
