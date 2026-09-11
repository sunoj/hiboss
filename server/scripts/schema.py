"""Check migration/schema parity using two fresh SQLite databases, or emit repair patches.
CLI: check-schema.sh [--regenerate] [--schema PATH]; uses Python standard library only.
"""

import argparse
import difflib
import re
import sqlite3
import sys
import tempfile
from pathlib import Path

from schema_sql import TOKEN, format_sql, normalize

SERVER = Path(__file__).resolve().parent.parent
MASTER_SQL = "SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name"
SchemaRow = tuple[str, str, str, str | None]


def snapshot(database: Path, sources: list[Path]) -> list[SchemaRow]:
    with sqlite3.connect(database) as connection:
        connection.execute('PRAGMA foreign_keys = ON')
        for source in sources:
            try:
                connection.executescript(source.read_text())
            except sqlite3.Error as error:
                raise RuntimeError(f'{source.name} failed on a fresh database: {error}') from error
        return connection.execute(MASTER_SQL).fetchall()


def normalized(rows: list[SchemaRow]) -> list[str]:
    # Include implicit constraint indexes (SQL NULL), not just explicit declarations.
    return [f'{kind} {name} ON {table}: {normalize(sql) if sql else "<implicit>"}\n'
            for kind, name, table, sql in rows]


def declarations(document: str) -> list[tuple[int, int, str]]:
    """Locate CREATE declarations while preserving surrounding prose and spacing."""
    result: list[tuple[int, int, str]] = []
    start: int | None = None
    for match in TOKEN.finditer(document):
        token = match.group()
        if token.upper() == 'CREATE' and start is None:
            start = match.start()
        if token == ';' and start is not None:
            sql = document[start:match.end()]
            words = normalize(sql).split()
            offset = 3 if words[1] == 'unique' else 2
            result.append((start, match.end(), words[offset]))
            start = None
    return result


def regenerated(document: str, rows: list[SchemaRow], version: str) -> str:
    expected = {name: sql for _, name, _, sql in rows if sql is not None}
    replacements: list[tuple[int, int, str]] = []
    for start, end, name in declarations(document):
        sql = expected.pop(name, None)
        if sql is None:
            replacements.append((start, end, ''))
        elif normalize(document[start:end]) != normalize(sql):
            formatted = format_sql(sql)
            if 'IF NOT EXISTS' in document[start:end].split('(', 1)[0]:
                formatted = re.sub(r'^(CREATE (?:UNIQUE )?(?:TABLE|INDEX)) ',
                                   r'\1 IF NOT EXISTS ', formatted)
            replacements.append((start, end, formatted))
    if expected:
        raise RuntimeError('Add documented domain placeholders before regenerating: '
                           + ', '.join(expected))
    for start, end, replacement in reversed(replacements):
        document = document[:start] + replacement + document[end:]
    header = (f'-- hiboss D1 schema: generated from migrations through {version}; '
              'regenerate with sh scripts/check-schema.sh --regenerate | patch schema.sql')
    return re.sub(r'\A[^\n]*', lambda _: header, document)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--schema', type=Path, default=SERVER / 'schema.sql')
    parser.add_argument('--regenerate', action='store_true', help='emit a targeted unified patch')
    args = parser.parse_args()
    # Filename order includes both historical 0002 migrations, without deduplication.
    migrations = sorted((SERVER / 'migrations').glob('[0-9][0-9][0-9][0-9]_*.sql'))
    if not migrations:
        raise RuntimeError('No migrations found')
    version = migrations[-1].name[:4]
    with tempfile.TemporaryDirectory(prefix='hiboss-schema-') as directory:
        root = Path(directory)
        migrated = snapshot(root / 'migrations.sqlite', migrations)
        if args.regenerate:
            original = args.schema.read_text()
            updated = regenerated(original, migrated, version)
            candidate = root / 'candidate.sql'
            candidate.write_text(updated)
            if normalized(snapshot(root / 'candidate.sqlite', [candidate])) != normalized(migrated):
                raise RuntimeError('Regenerated schema failed parity validation')
            sys.stdout.writelines(difflib.unified_diff(original.splitlines(True), updated.splitlines(True),
                                                     fromfile='schema.sql', tofile='schema.sql'))
            return 0
        consolidated = snapshot(root / 'schema.sqlite', [args.schema])
        difference = list(difflib.unified_diff(normalized(migrated), normalized(consolidated),
                                             fromfile='migrations', tofile='schema.sql'))
        if difference:
            sys.stderr.writelines(difference)
            return 1
        tables = sum(row[0] == 'table' for row in migrated)
        indexes = sum(row[0] == 'index' for row in migrated)
        print(f'Schema matches {len(migrations)} migrations through {version}: '
              f'{tables} tables, {indexes} indexes (including implicit constraint indexes).')
        return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError) as error:
        sys.exit(str(error))
