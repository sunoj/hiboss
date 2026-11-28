"""Verify the chat-channel migration against a populated SQLite database.
Uses the standard library and the ordered D1 migration files.
"""

import sqlite3
from pathlib import Path

db = sqlite3.connect(':memory:')
db.execute('PRAGMA foreign_keys = ON')
directory = Path(__file__).resolve().parent.parent / 'migrations'
removal = directory / '0072_remove_chat_channels.sql'
for migration in sorted(directory.glob('*.sql')):
    if migration == removal:
        break
    db.executescript(migration.read_text())
db.executescript("""
INSERT INTO api_keys (id, name, channel_routing) VALUES ('agent', 'Agent', '{}');
INSERT INTO bosses (id, name, telegram_user_id, discord_user_id) VALUES ('boss', 'Boss', '123', '456');
INSERT INTO sessions (id, agent_id, discord_thread_id, telegram_topic_id) VALUES ('session', 'agent', '789', 222);
INSERT INTO messages (id, agent_id, direction, mode, channel, body, metadata)
VALUES ('message', 'agent', 'agent_to_boss', 'async', 'discord', 'History', '{"source":"discord"}');
INSERT INTO channel_providers (id, provider, label, credentials) VALUES ('chat', 'discord', 'Chat', '{}');
INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label)
VALUES ('chat', 'boss', 'discord_channel', 'chat', '{}', 'Chat'),
       ('push', 'boss', 'apns', NULL, '{}', 'Push'), ('native', 'boss', 'native_live', NULL, '{}', 'Live');
INSERT INTO message_deliveries (id, message_id, destination_id, status, merged_into)
VALUES ('push-receipt', 'message', 'push', 'sent', NULL),
       ('native-receipt', 'message', 'native', 'sent', 'push-receipt'),
       ('chat-receipt', 'message', 'chat', 'sent', NULL);
INSERT INTO delivery_queue (id, message_id, agent_id, channel, config, scheduled_at)
VALUES ('queued-chat', 'message', 'agent', 'discord', '{"bot_token":"fixture"}', '2000-01-01'),
       ('queued-app', 'message', 'agent', 'api', '{}', '2000-01-01');
""")
db.executescript('BEGIN;\n' + removal.read_text() + '\nCOMMIT;')
assert db.execute('PRAGMA foreign_key_check').fetchall() == []
assert db.execute('SELECT channel, metadata FROM messages').fetchall() == [('discord', '{"source":"discord"}')]
assert db.execute('SELECT kind FROM boss_destinations ORDER BY kind').fetchall() == [('apns',), ('native_live',)]
assert db.execute('SELECT id, status, merged_into FROM message_deliveries ORDER BY id').fetchall() == [
    ('native-receipt', 'sent', 'push-receipt'), ('push-receipt', 'sent', None),
]
assert db.execute('SELECT config, status FROM delivery_queue ORDER BY id').fetchall() == [
    ('{"native_only":true}', 'pending'), ('{}', 'failed'),
]
print('Migration upgrade fixture passed with foreign keys enabled.')
