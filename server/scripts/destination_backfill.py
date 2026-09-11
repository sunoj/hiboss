"""Verify additive destination backfill against production-shaped legacy rows.
Entrypoint for schema Vitest checks; uses standard-library SQLite and migrations.
"""
import json
import sqlite3
from pathlib import Path


def seed(db: sqlite3.Connection) -> None:
    for agent in range(4):
        db.execute('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)',
                   (f'a{agent}', f'agent{agent}', f'hash{agent}'))
        db.execute('INSERT INTO sessions (id, agent_id, label, discord_thread_id, telegram_topic_id) '
                   'VALUES (?, ?, ?, ?, ?)', (f's{agent}', f'a{agent}', f'project{agent}/main', f't{agent}', 100 + agent))
    db.execute("INSERT INTO bosses (id, name, role) VALUES ('admin', 'Admin', 'admin'), ('manager', 'Manager', 'manager')")
    db.executemany("INSERT INTO boss_agent_access VALUES ('manager', ?)", [('a0',), ('a1',)])
    for agent in range(4):
        config = {'bot_token': 'telegram-token', 'chat_id': 'shared' if agent < 2 else f'chat{agent}', 'message_thread_id': 10 + agent}
        db.execute("INSERT INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, 'telegram', ?, ?)",
                   (f'tg{agent}', f'a{agent}', json.dumps(config), 0 if agent in (1, 3) else 1))
    for agent in range(3):
        config = {'webhook_url': 'https://discord.com/api/webhooks/1/token', 'bot_token': 'discord-token', 'channel_id': 'discord-shared', 'use_threads': True}
        db.execute("INSERT INTO channel_configs (id, agent_id, channel, config) VALUES (?, ?, 'discord', ?)",
                   (f'dc{agent}', f'a{agent}', json.dumps(config)))
    db.execute("INSERT INTO boss_clients (id, boss_id, kind, label) VALUES ('ios', 'admin', 'ios', 'Phone'), ('mac', 'manager', 'macos', 'Mac'), ('web', 'admin', 'web', 'Browser')")
    db.execute("INSERT INTO boss_devices (id, boss_id, client_id, device_token, bundle_id, environment) VALUES ('push', 'admin', 'ios', 'token', 'app', 'sandbox')")
    db.execute("INSERT INTO messages (id, agent_id, direction, mode, body) VALUES ('message', 'a0', 'agent_to_boss', 'async', 'untouched')")


def verify(db: sqlite3.Connection, messages: list[tuple], columns: list[tuple]) -> None:
    assert db.execute('SELECT * FROM messages').fetchall() == messages
    assert db.execute('PRAGMA table_info(messages)').fetchall() == columns
    assert db.execute('SELECT COUNT(*) FROM channel_configs').fetchone() == (7,)
    assert db.execute('SELECT COUNT(*) FROM channel_providers').fetchone() == (2,)
    assert db.execute('SELECT COUNT(*) FROM boss_destinations').fetchone() == (9,)
    assert db.execute("SELECT COUNT(*) FROM boss_destinations WHERE boss_id = 'manager' AND provider_id IS NOT NULL").fetchone() == (2,)
    assert db.execute("SELECT enabled FROM boss_destinations WHERE json_extract(target, '$.chat_id') = 'chat3'").fetchone() == (0,)
    assert db.execute("SELECT COUNT(*) FROM boss_destinations WHERE json_extract(target, '$.chat_id') = 'shared' AND enabled = 1").fetchone() == (2,)
    assert db.execute('SELECT COUNT(*) FROM destination_routes WHERE session_id IS NOT NULL').fetchone() == (11,)
    assert db.execute("SELECT COUNT(*) FROM destination_routes WHERE session_id = 's1' AND external_thread_id = '101'").fetchone() == (2,)
    assert db.execute("SELECT COUNT(*) FROM destination_routes WHERE session_id = 's1' AND external_thread_id = 't1'").fetchone() == (2,)
    assert db.execute("SELECT COUNT(*) FROM destination_routes WHERE project = 'agent1' AND external_thread_id = '11'").fetchone() == (2,)
    assert db.execute("SELECT client_id, target FROM boss_destinations WHERE kind = 'apns'").fetchone() == ('ios', '{"device_id":"push"}')
    assert db.execute("SELECT COUNT(*) FROM boss_destinations WHERE kind = 'native_live'").fetchone() == (2,)
    assert not db.execute('PRAGMA foreign_key_check').fetchall()


def main() -> None:
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys = ON')
    for migration in sorted(Path('migrations').glob('*.sql')):
        if migration.name.startswith('0040_'):
            break
        db.executescript(migration.read_text())
    seed(db)
    messages = db.execute('SELECT * FROM messages').fetchall()
    columns = db.execute('PRAGMA table_info(messages)').fetchall()
    db.executescript(Path('migrations/0040_destinations.sql').read_text())
    verify(db, messages, columns)


if __name__ == '__main__':
    main()
