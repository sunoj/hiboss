"""Validate migration 0045 against the seven-agent production shape.
Uses SQLite with FK enforcement and the real migration history; no production access.
"""
import hashlib
import sqlite3
from pathlib import Path


def seed(db: sqlite3.Connection) -> None:
    for number in range(7):
        key_hash = hashlib.sha256(f'hb_existing_{number}'.encode()).hexdigest()
        role = 'admin' if number == 0 else ('worker' if number % 2 else None)
        db.execute('INSERT INTO api_keys (id, name, key_hash, role, callback_url, session_info, '
                   'last_used_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
                   (str(number), f'agent-{number}', key_hash, role, 'https://callback.test',
                    '{"branch":"main"}', '2026-09-11 10:00:00'))
    db.execute("INSERT INTO bosses (id, name, agent_id) VALUES ('boss', 'Boss', '0')")
    db.execute("INSERT INTO boss_agent_access VALUES ('boss', '0')")
    db.execute("INSERT INTO sessions (id, agent_id) VALUES ('session', '1')")
    db.execute("INSERT INTO agent_groups (id, name, owner_id) VALUES ('group', 'Group', '2')")
    db.execute("INSERT INTO agent_group_members (group_id, agent_id) VALUES ('group', '2')")
    db.executemany("INSERT INTO messages (id, agent_id, direction, mode, body) "
                   "VALUES (?, ?, 'agent_to_boss', 'async', 'existing')",
                   [(str(n), str(n % 7)) for n in range(29006)])


def verify(db: sqlite3.Connection, before: list[tuple], children: dict) -> None:
    agents = db.execute('SELECT id, name, key_hash, callback_url, session_info, created_at, last_used_at '
                        'FROM api_keys ORDER BY id').fetchall()
    assert agents == before
    for name, (sql, root, rows) in children.items():
        assert db.execute('SELECT sql, rootpage FROM sqlite_master WHERE name = ?', (name,)).fetchone() == (sql, root)
        assert db.execute(f'SELECT * FROM "{name}"').fetchall() == rows
    assert db.execute('SELECT count(*) FROM agent_keys').fetchone() == (7,)
    assert db.execute("SELECT count(*) FROM agent_keys k JOIN api_keys a ON a.id = k.agent_id "
                      "WHERE k.key_hash = a.key_hash AND k.label = 'migrated' "
                      "AND k.created_at = a.created_at AND k.last_used_at = a.last_used_at "
                      "AND k.revoked_at IS NULL").fetchone() == (7,)
    assert db.execute("SELECT role, is_admin FROM api_keys WHERE id = '0'").fetchone() == (None, 1)
    assert db.execute("SELECT role, is_admin FROM api_keys WHERE id = '1'").fetchone() == ('worker', 0)
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    db.execute("INSERT INTO api_keys (id, name) VALUES ('new', 'New')")
    assert db.execute("SELECT key_hash, is_admin FROM api_keys WHERE id = 'new'").fetchone() == (None, 0)
    db.execute("INSERT INTO agent_keys (agent_id, key_hash, label) VALUES ('new', 'hash', 'Mac')")
    db.execute("DELETE FROM api_keys WHERE id = 'new'")
    assert db.execute("SELECT count(*) FROM agent_keys WHERE agent_id = 'new'").fetchone() == (0,)


def main() -> None:
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys = ON')
    for migration in sorted(Path('migrations').glob('*.sql')):
        if migration.name.startswith('0045_'):
            break
        db.executescript(migration.read_text())
    seed(db)
    before = db.execute('SELECT id, name, key_hash, callback_url, session_info, created_at, last_used_at '
                        'FROM api_keys ORDER BY id').fetchall()
    children = {name: (sql, root, db.execute(f'SELECT * FROM "{name}"').fetchall())
                for name, sql, root in db.execute("SELECT name, sql, rootpage FROM sqlite_master "
                                                  "WHERE type = 'table' AND name != 'api_keys'").fetchall()}
    migration = Path('migrations/0045_agent_keys.sql').read_text()
    db.commit()
    db.executescript('BEGIN;\n' + migration + '\nCOMMIT;')
    verify(db, before, children)


if __name__ == '__main__':
    main()
