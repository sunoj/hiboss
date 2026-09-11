// Verifies migration 0041 backfills both providers and preserves legacy rows.
// Depends on Python SQLite for a production-order migration replay.
import { spawnSync } from 'node:child_process';
import { expect, it } from 'vitest';
it('backfills external accounts with uniqueness and cascades, leaving legacy data untouched', () => {
  const script = `
import sqlite3
from pathlib import Path
db = sqlite3.connect(':memory:')
db.execute('PRAGMA foreign_keys=ON')
files = sorted(Path('migrations').glob('*.sql'))
for file in files:
    if file.name.startswith('0041'): break
    db.executescript(file.read_text())
db.execute("INSERT INTO bosses (id, name, telegram_user_id, discord_user_id) VALUES ('b', 'Boss', '123', '456')")
legacy = {table: db.execute('SELECT * FROM ' + table).fetchall() for table in ['bosses', 'messages', 'channel_configs', 'delivery_queue']}
db.executescript(file.read_text())
assert db.execute('SELECT provider, provider_user_id FROM boss_external_accounts ORDER BY provider').fetchall() == [('discord', '456'), ('telegram', '123')]
for table, rows in legacy.items(): assert db.execute('SELECT * FROM ' + table).fetchall() == rows
try:
    db.execute("INSERT INTO boss_external_accounts (boss_id, provider, provider_user_id) VALUES ('b', 'telegram', '123')")
    raise AssertionError('duplicate accepted')
except sqlite3.IntegrityError: pass
db.execute("DELETE FROM bosses WHERE id='b'")
assert db.execute('SELECT COUNT(*) FROM boss_external_accounts').fetchone()[0] == 0
`;
  const result = spawnSync('python3', ['-c', script], { encoding: 'utf8' });
  expect(result.status, result.stdout + result.stderr).toBe(0);
});
