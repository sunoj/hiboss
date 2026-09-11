"""Verify additive project backfill with production-shaped SQLite fixtures.
Runs under schema Vitest; uses migration SQL and Python's standard SQLite driver.
"""
import sqlite3
import unittest
from pathlib import Path

MIGRATIONS = Path(__file__).resolve().parent.parent / 'migrations'


def database():
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys = ON')
    for path in sorted(MIGRATIONS.glob('*.sql')):
        if path.name < '0043':
            db.executescript(path.read_text())
    db.execute("INSERT INTO api_keys (id, name, key_hash) VALUES ('agent', 'agent', 'hash')")
    return db


def migrate(db):
    db.executescript((MIGRATIONS / '0043_projects.sql').read_text())


class ProjectBackfill(unittest.TestCase):
    def test_links_production_shaped_rows_and_preserves_messages(self):
        db = database()
        db.execute("INSERT INTO progress_teams (project, handle, display_name, bio, avatar_url, created_by_agent_id) VALUES ('HiBoss', 'hiboss', 'Hi Boss', 'bio', '/avatar', 'agent')")
        db.executemany("INSERT INTO sessions (id, agent_id, label) VALUES (?, 'agent', ?)",
                       [('s1', 'HiBoss/main'), ('s2', 'Solo'), ('s3', None), ('s4', ''), ('s5', '/branch')])
        db.execute("INSERT INTO progress_posts (id, agent_id, project, body) VALUES ('post', 'agent', 'HiBoss', 'body')")
        db.execute("INSERT INTO bosses (id, name) VALUES ('boss', 'Boss')")
        db.execute("INSERT INTO boss_destinations (id, boss_id, kind, label, target) VALUES ('dest', 'boss', 'native_live', 'Test', '{}')")
        db.execute("INSERT INTO destination_routes (id, destination_id, project, session_id) VALUES ('route', 'dest', 'HiBoss', 's1')")
        db.execute("INSERT INTO messages (agent_id, direction, mode, body) VALUES ('agent', 'agent_to_boss', 'async', 'untouched')")
        messages = db.execute('SELECT * FROM messages').fetchall()
        schema = db.execute("SELECT sql FROM sqlite_master WHERE name = 'messages'").fetchone()
        migrate(db)
        self.assertEqual(db.execute('SELECT COUNT(*) FROM projects').fetchone()[0], 2)
        project = db.execute("SELECT id, slug, display_name, bio, avatar_url, created_by_agent_id FROM projects WHERE handle = 'hiboss'").fetchone()
        self.assertEqual(project[1:], ('hiboss', 'Hi Boss', 'bio', '/avatar', 'agent'))
        for table, row in [('sessions', 's1'), ('progress_posts', 'post'), ('destination_routes', 'route')]:
            self.assertEqual(db.execute(f'SELECT project_id FROM {table} WHERE id = ?', (row,)).fetchone()[0], project[0])
        self.assertEqual(db.execute("SELECT COUNT(*) FROM sessions WHERE project_id IS NULL").fetchone()[0], 3)
        self.assertEqual(db.execute('SELECT * FROM messages').fetchall(), messages)
        self.assertEqual(db.execute("SELECT sql FROM sqlite_master WHERE name = 'messages'").fetchone(), schema)
        self.assertEqual(db.execute('SELECT COUNT(*) FROM progress_teams').fetchone()[0], 1)
        self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_preserves_distinct_values_when_slugs_collide(self):
        db = database()
        values = ['Hello World', 'hello-world', 'hello--world', '!!!', '项目', 'project']
        db.executemany("INSERT INTO progress_posts (agent_id, project, body) VALUES ('agent', ?, 'body')", [(v,) for v in values])
        migrate(db)
        slugs = [row[0] for row in db.execute('SELECT slug FROM projects')]
        self.assertEqual(len(set(slugs)), len(values))
        for slug in slugs:
            self.assertRegex(slug, r'^[a-z0-9_-]+$')
        self.assertEqual(db.execute('SELECT COUNT(DISTINCT project_id) FROM project_aliases').fetchone()[0], len(values))

    def test_duplicate_agent_names_fail_loudly_before_project_changes(self):
        db = database()
        db.execute("INSERT INTO api_keys (id, name, key_hash) VALUES ('duplicate', 'agent', 'different')")
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'duplicate_api_keys_names'):
            migrate(db)
        self.assertIsNone(db.execute("SELECT name FROM sqlite_master WHERE name = 'projects'").fetchone())

    def test_new_agent_name_uniqueness_and_alias_cascade(self):
        db = database()
        migrate(db)
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'api_keys.name'):
            db.execute("INSERT INTO api_keys (name, key_hash) VALUES ('agent', 'new')")
        db.execute("INSERT INTO projects (id, slug, display_name) VALUES ('p', 'p', 'P')")
        db.execute("INSERT INTO project_aliases (alias, project_id, source) VALUES ('old', 'p', 'cwd')")
        db.execute("DELETE FROM projects WHERE id = 'p'")
        self.assertEqual(db.execute('SELECT COUNT(*) FROM project_aliases').fetchone()[0], 0)


if __name__ == '__main__':
    unittest.main()
