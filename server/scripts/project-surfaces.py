"""Verify phase 3b guards and preservation with the full SQLite migration chain.
Exports unittest fixtures; depends only on Python sqlite3 and pathlib.
"""
import pathlib
import sqlite3
import unittest

MIGRATIONS = pathlib.Path('migrations')


def database():
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys = ON')
    for path in sorted(MIGRATIONS.glob('*.sql')):
        if path.name.startswith('0044'):
            break
        db.executescript(path.read_text())
    return db


class Surfaces(unittest.TestCase):
    def test_preserves_posts_likes_and_messages(self):
        db = database()
        db.execute("INSERT INTO api_keys (id, name, key_hash) VALUES ('a', 'a', 'a')")
        db.execute("INSERT INTO bosses (id, name) VALUES ('b', 'b')")
        db.execute("INSERT INTO projects (id, slug, display_name) VALUES ('p', 'repo', 'Repo')")
        db.execute("INSERT INTO project_aliases (alias, project_id, source) VALUES ('repo', 'p', 'explicit')")
        db.execute("INSERT INTO progress_teams (project, handle, display_name) VALUES ('repo', 'repo', 'Repo')")
        db.execute("INSERT INTO progress_posts (id, agent_id, project_id, project, body) VALUES ('post', 'a', 'p', 'old-text', 'preserved')")
        db.execute("INSERT INTO progress_likes (post_id, boss_id) VALUES ('post', 'b')")
        db.execute("INSERT INTO messages (agent_id, direction, mode, body) VALUES ('a', 'agent_to_boss', 'async', 'untouched')")
        before = {table: db.execute(f'SELECT * FROM {table}').fetchall()
                  for table in ['messages', 'progress_posts', 'progress_likes']}
        db.executescript((MIGRATIONS / '0044_project_surfaces.sql').read_text())
        for table, rows in before.items():
            self.assertEqual(rows, db.execute(f'SELECT * FROM {table}').fetchall())
        db.execute("INSERT INTO progress_posts (agent_id, project_id, body) VALUES ('a', 'p', 'new')")
        self.assertEqual(db.execute("SELECT project FROM progress_posts WHERE body = 'new'").fetchone(), (None,))
        self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(), [])
        self.assertIsNone(db.execute("SELECT name FROM sqlite_master WHERE name = 'progress_teams'").fetchone())

    def test_rejects_an_uncopied_team(self):
        db = database()
        db.execute("INSERT INTO progress_teams (project, handle, display_name) VALUES ('lost', 'lost', 'Lost')")
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'missing_team_project'):
            db.executescript((MIGRATIONS / '0044_project_surfaces.sql').read_text())
        self.assertEqual(db.execute('SELECT COUNT(*) FROM progress_teams').fetchone(), (1,))


if __name__ == '__main__':
    unittest.main()
