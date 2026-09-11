"""Exercise migration 0039 against legacy tokens, keys, and push registrations.
Entrypoint for the Node Vitest integration suite; uses standard-library SQLite.
"""
import sqlite3
from pathlib import Path


def seed(db: sqlite3.Connection) -> None:
    for boss in ('signed', 'unsigned', 'push-only'):
        db.execute('INSERT INTO bosses (id, name) VALUES (?, ?)', (boss, boss))
    for token, boss, created, revoked in [
        ('ios-old', 'signed', '2020-01-01', None),
        ('ios-new', 'signed', '2021-01-01', None),
        ('mac', 'signed', '2022-01-01', None),
        ('web', 'unsigned', '2020-01-01', None),
        ('dead', 'unsigned', '2020-01-01', '2020-02-01'),
    ]:
        db.execute('INSERT INTO boss_tokens (id, boss_id, label, token_hash, created_at, revoked_at) '
                   'VALUES (?, ?, ?, ?, ?, ?)', (token, boss, token, token, created, revoked))
    for token, kind, boss in [('ios-old', 'ios', 'signed'), ('ios-new', 'ios', 'signed'),
                               ('mac', 'macos', 'signed'), ('dead', 'ios', 'unsigned')]:
        db.execute("INSERT INTO boss_signing_keys (id, boss_id, boss_token_id, algorithm, client_kind, public_key) "
                   "VALUES (?, ?, ?, 'ES256', ?, 'public')", (token, boss, token, kind))
    for device, boss in [('one', 'signed'), ('two', 'unsigned'), ('three', 'push-only'), ('four', 'push-only')]:
        db.execute("INSERT INTO boss_devices (id, boss_id, device_token, bundle_id, environment) "
                   "VALUES (?, ?, ?, 'app', 'sandbox')", (device, boss, device))


def verify(db: sqlite3.Connection, credentials: list[tuple]) -> None:
    assert db.execute('SELECT id, token_hash, revoked_at FROM boss_tokens ORDER BY id').fetchall() == credentials
    assert db.execute('SELECT COUNT(*) FROM boss_clients').fetchone() == (6,)
    assert db.execute('SELECT kind, label FROM boss_clients WHERE id = ?', ('client_mac',)).fetchone() == ('macos', 'mac')
    assert db.execute('SELECT kind, label FROM boss_clients WHERE id = ?', ('client_web',)).fetchone() == ('web', 'web')
    assert db.execute('SELECT client_id FROM boss_tokens WHERE id = ?', ('dead',)).fetchone() == (None,)
    assert db.execute('SELECT client_id FROM boss_signing_keys WHERE id = ?', ('dead',)).fetchone() == (None,)
    assert db.execute('SELECT COUNT(*) FROM boss_signing_keys k JOIN boss_tokens t ON t.id = k.boss_token_id '
                      'WHERE k.client_id = t.client_id').fetchone() == (3,)
    assert db.execute("SELECT client_id FROM boss_devices WHERE id = 'one'").fetchone() == ('client_ios-new',)
    assert db.execute("SELECT COUNT(*) FROM boss_devices d JOIN boss_clients c ON c.id = d.client_id "
                      "WHERE c.kind = 'ios' AND c.label = 'migrated-push'").fetchone() == (3,)
    assert db.execute("SELECT COUNT(DISTINCT client_id) FROM boss_devices WHERE boss_id = 'push-only'").fetchone() == (1,)
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    db.execute("DELETE FROM bosses WHERE id = 'signed'")
    assert db.execute("SELECT COUNT(*) FROM boss_clients WHERE boss_id = 'signed'").fetchone() == (0,)


def main() -> None:
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys = ON')
    migrations = sorted(Path('migrations').glob('*.sql'))
    for migration in migrations:
        if migration.name.startswith('0039_'):
            break
        db.executescript(migration.read_text())
    seed(db)
    credentials = db.execute('SELECT id, token_hash, revoked_at FROM boss_tokens ORDER BY id').fetchall()
    db.executescript(Path('migrations/0039_boss_clients.sql').read_text())
    verify(db, credentials)


if __name__ == '__main__':
    main()
