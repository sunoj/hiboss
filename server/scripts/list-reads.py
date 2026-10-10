"""Measure dashboard SQL from the route sources on production-sized local fixtures.
Uses SQLite scan-status counters, checks plans and compares complete result rows.
"""
import argparse
import ctypes
import ctypes.util
import json
from pathlib import Path
import re
import sqlite3
import tempfile
from list_reads_cases import message_cases, previous_indexes, reference_page


# The migration under test; every other migration forms the base schema.
CHANGE_MIGRATION = '0051_dashboard_list_order.sql'

def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def seed(db, root, size):
    for migration in sorted((root / 'migrations').glob('*.sql')):
        if migration.name != CHANGE_MIGRATION:
            db.executescript(migration.read_text())
    db.executemany('INSERT INTO api_keys (id, name) VALUES (?, ?)',
                   [(f'agent-{i:02}', f'Agent {i}') for i in range(13)])
    db.executemany('INSERT INTO projects (id, slug, display_name) VALUES (?, ?, ?)',
                   [(f'project-{i}', f'project-{i}', f'Project {i}') for i in range(7)])
    db.execute("""WITH RECURSIVE volumes(id, ceiling) AS (VALUES
        (0,1400),(1,2400),(2,3100),(3,3600),(4,3950),(5,4200),(6,4400),
        (7,4550),(8,4650),(9,4710),(10,4761),(11,4800),(12,4817)),
        n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<4816)
        INSERT INTO sessions (id, agent_id, project_id, label, branch, last_seen_at)
        SELECT 'session-'||x, (SELECT printf('agent-%02d', id) FROM volumes
          WHERE (x*7919)%4817 < ceiling ORDER BY id LIMIT 1),
        CASE WHEN x%23=0 THEN 'missing-project' ELSE 'project-'||(x%7) END, 'old/topic',
        CASE WHEN x%3=0 THEN NULL ELSE 'branch' END,
        datetime('now', CASE WHEN x<40 AND (x*7919)%4817<4761 THEN '-1 minute' ELSE '-1 day' END) FROM n""")
    db.execute("""WITH RECURSIVE volumes(id, ceiling) AS (VALUES
        (0,8777),(1,14777),(2,19177),(3,22377),(4,24677),(5,26377),(6,27677),
        (7,28577),(8,29077),(9,29427),(10,29742),(11,29954),(12,30044)),
        n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<?)
        INSERT INTO messages (id, agent_id, session_id, direction, mode, body, status, created_at)
        SELECT 'message-'||x, (SELECT printf('agent-%02d', id) FROM volumes
          WHERE (x*7919)%? < ceiling*?/30044 ORDER BY id LIMIT 1), 'session-'||(x%4817),
        CASE WHEN x%5<3 THEN 'agent_to_boss' ELSE 'boss_to_agent' END, 'async', 'body '||x,
        CASE WHEN x%2=0 THEN 'sent' ELSE 'read' END,
        datetime('2026-01-01', '+'||(x/26)||' seconds') FROM n""", (size - 1, size, size))
    db.commit()


def route_sql(root, file, prefix):
    source = (root / 'src/routes' / file).read_text()
    return next(sql for sql in re.findall(r'`([^`]+)`', source) if sql.startswith(prefix))


def message_sql(root, where, index, limit, offset):
    sql = route_sql(root, 'boss-api-messages.ts', 'SELECT messages.*')
    return (sql.replace('${where}', where).replace('${index}', index)
            .replace('LIMIT ?', f'LIMIT {limit}').replace('OFFSET ?', f'OFFSET {offset}'))


def session_sql(root, ids, inactive):
    sql = route_sql(root, 'boss-api.ts', 'SELECT s.*')
    sql = sql.replace('${placeholders}', ids)
    sql = re.sub(r'\$\{c.req.query\(.*?\}',
                 '' if inactive else "AND s.last_seen_at > datetime('now', '-15 minutes')", sql)
    return sql.replace('${SESSION_LABEL_SQL}', label_sql(root))


def label_sql(root):
    source = (root / 'src/projects/session-label.ts').read_text()
    branch = re.search(r'const BRANCH = "(.*)";', source)[1]
    return re.search(r'SESSION_LABEL_SQL = `([^`]+)`', source)[1].replace('${BRANCH}', branch)


def rows(db, sql):
    cursor = db.execute(sql)
    names = [column[0] for column in cursor.description]
    return [dict(zip(names, row)) for row in cursor]


def visited(enabled, path, sql):
    if not enabled:
        return None
    library = ctypes.CDLL(ctypes.util.find_library('sqlite3'))
    pointer = ctypes.c_void_p
    library.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(pointer)]
    library.sqlite3_prepare_v2.argtypes = [pointer, ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(pointer), pointer]
    library.sqlite3_step.argtypes = [pointer]
    library.sqlite3_finalize.argtypes = [pointer]
    library.sqlite3_close.argtypes = [pointer]
    library.sqlite3_stmt_scanstatus.argtypes = [pointer, ctypes.c_int, ctypes.c_int, pointer]
    db, statement = pointer(), pointer()
    assert library.sqlite3_open(str(path).encode(), ctypes.byref(db)) == 0
    try:
        assert library.sqlite3_prepare_v2(db, sql.encode(), -1, ctypes.byref(statement), None) == 0, sql
        while True:
            result = library.sqlite3_step(statement)
            if result != 100:  # SQLITE_ROW
                assert result == 101, result  # SQLITE_DONE
                break
        total, loop = 0, 0
        count = ctypes.c_int64()
        while library.sqlite3_stmt_scanstatus(statement, loop, 1, ctypes.byref(count)) == 0:
            total += count.value  # SQLITE_SCANSTAT_NVISIT, before shell K/M rounding
            loop += 1
        return total
    finally:
        library.sqlite3_finalize(statement)
        library.sqlite3_close(db)


def session_metadata(db, root, result):
    source = (root / 'src/routes/session-list.ts').read_text()
    queries = re.findall(r"prepare\('(SELECT [^']+)'\)", source)
    ids = [[row['agent_id'] for row in result], [row['project_id'] for row in result if row['project_id']]]
    sql = [query.replace('?', literal(json.dumps(sorted(set(values))))) for query, values in zip(queries, ids)]
    names = {row['id']: row['name'] for row in rows(db, sql[0])}
    projects = {row['id']: row for row in rows(db, sql[1])}
    hydrated = []
    for row in result:
        project = projects.get(row['project_id'])
        branch = row['branch']
        if branch is None:
            branch = row['label'].split('/', 1)[1] if '/' in (row['label'] or '') else ''
        label = (project['slug'] + ('/' + branch if branch else '')) if project else row['label']
        hydrated.append({**row, 'agent_name': names.get(row['agent_id']), 'label': label,
                         'project_slug': project['slug'] if project else None,
                         'project_display_name': project['display_name'] if project else None})
    return hydrated, sql


def measure_messages(root, scanstats, base, current, base_path, new_path, prior_path, report, check):
    source = (root / 'src/routes/boss-api-messages.ts').read_text()
    indexes = re.findall(r"'INDEXED BY ([^']+)'", source)
    for name, agents, direction, offset in message_cases(base):
        ids = ', '.join(map(literal, agents))
        where = f'agent_id IN ({ids})' + (" AND direction = 'agent_to_boss'" if direction == 'boss' else '')
        count = f'SELECT COUNT(*) AS total FROM messages WHERE {where}'
        total = rows(base, count)[0]['total']
        assert rows(base, count) == rows(current, count)
        index = indexes[direction == 'boss']
        new = message_sql(root, where, f'INDEXED BY {index}', 50, offset)
        skipped = offset >= total and 'offset >= total' in source
        details = [] if skipped else [row[3] for row in current.execute('EXPLAIN QUERY PLAN ' + new)]
        oracle = reference_page(where, offset, 'canonical', direction)
        assert rows(base, oracle) == ([] if skipped else rows(current, new)), name
        page_visits = [visited(scanstats, base_path, reference_page(where, offset, 'main', direction)),
                       visited(scanstats, prior_path, reference_page(where, offset, 'previous', direction, len(agents))),
                       0 if skipped else visited(scanstats, new_path, new)]
        counts = [visited(scanstats, path, count) for path in [base_path, prior_path, new_path]]
        report['queries'][name] = {'page_main_previous_fixed': page_visits, 'count_main_previous_fixed': counts,
                                  'total': total, 'plan': details}
        if check:
            bound = len(agents) * (50 + offset + 1) + 100 if offset < total else 0
            assert page_visits[2] is None or page_visits[2] <= bound, (name, page_visits, bound)
            assert skipped or any('SEARCH messages USING INDEX ' + index in detail for detail in details), details


def measure_sessions(root, scanstats, base, current, base_path, new_path, prior_path, ids, report, check):
    for inactive in [False, True]:
        active = '' if inactive else "AND s.last_seen_at > datetime('now', '-15 minutes')"
        old = f'''SELECT s.*, api_keys.name AS agent_name, p.slug AS project_slug,
            p.display_name AS project_display_name, {label_sql(root)} AS label FROM sessions s
            LEFT JOIN projects p ON p.id=s.project_id LEFT JOIN api_keys ON api_keys.id=s.agent_id
            WHERE s.agent_id IN ({ids}) {active} ORDER BY s.last_seen_at DESC'''
        new = session_sql(root, ids, inactive)
        actual = rows(current, new)
        metadata = []
        if 'JOIN' not in new:
            actual, metadata = session_metadata(current, root, actual)
        assert rows(base, old) == actual, 'session parity'
        details = [row[3] for row in current.execute('EXPLAIN QUERY PLAN ' + new)]
        before = visited(scanstats, base_path, old)
        after = sum(visited(True, new_path, sql) for sql in [new, *metadata]) if scanstats else None
        prior_sql = new.replace('FROM sessions s WHERE', 'FROM sessions s INDEXED BY idx_sessions_seen WHERE')
        prior = sum(visited(True, prior_path, sql) for sql in [prior_sql, *metadata]) if scanstats else None
        report['queries'][f'sessions_{ids}_inactive_{inactive}'] = {
            'main_previous_fixed': [before, prior, after], 'returned': len(actual), 'plan': details}
        if check:
            assert any('idx_sessions_agent' in detail for detail in details), details
            assert 'INDEXED BY' not in new, new
            assert after is None or after <= before, (before, after)


def measure(root, scanstats, size, check):
    with tempfile.TemporaryDirectory(prefix='hiboss-list-reads-') as directory:
        base_path, prior_path, new_path = [Path(directory) / name for name in ['base.db', 'prior.db', 'new.db']]
        base = sqlite3.connect(base_path)
        seed(base, root, size)
        current = sqlite3.connect(new_path)
        base.backup(current)
        prior = sqlite3.connect(prior_path)
        base.backup(prior)
        prior.executescript(previous_indexes)
        for migration in sorted((root / 'migrations').glob('*.sql')):
            if migration.name == CHANGE_MIGRATION:
                current.executescript(migration.read_text())
        ids = ', '.join(literal(f'agent-{i:02}') for i in range(13))
        report = {'messages': size, 'agents': 13, 'sessions': 4817, 'queries': {}}
        measure_messages(root, scanstats, base, current, base_path, new_path, prior_path, report, check)
        for scope in [ids, literal('agent-12'), literal('agent-11') + ', ' + literal('agent-12')]:
            measure_sessions(root, scanstats, base, current, base_path, new_path, prior_path, scope, report, check)
        return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--scanstats', action='store_true', help='Requires system SQLite with SQLITE_ENABLE_STMT_SCANSTATUS')
    parser.add_argument('--messages', type=int, default=30044)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    print(json.dumps(measure(args.root, args.scanstats, args.messages, args.check), indent=2))
