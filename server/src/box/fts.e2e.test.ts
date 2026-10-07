// Proves D1 FTS5 support inside the repository's actual Workers test pool.
// Exercises virtual table creation, token matching and relevance ranking.
import { env } from 'cloudflare:test';
import { expect, it } from 'vitest';

it('creates an FTS5 table and ranks matches in the Workers pool', async () => {
  await env.DB.prepare('CREATE VIRTUAL TABLE box_fts_probe USING fts5(text, note, url, tags)').run();
  await env.DB.prepare('INSERT INTO box_fts_probe VALUES (?, ?, ?, ?)')
    .bind('layout layout layout', 'reference', 'https://example.com', '["design"]').run();
  await env.DB.prepare('INSERT INTO box_fts_probe VALUES (?, ?, ?, ?)')
    .bind('layout with many other words to dilute the match', '', '', '[]').run();
  const rows = await env.DB.prepare(`SELECT rowid, bm25(box_fts_probe) AS score
    FROM box_fts_probe WHERE box_fts_probe MATCH ? ORDER BY score`)
    .bind('layout').all<{ rowid: number; score: number }>();
  expect(rows.results).toHaveLength(2);
  expect(rows.results[0].rowid).toBe(1);
  expect(rows.results[0].score).toBeLessThan(rows.results[1].score);
  const tags = await env.DB.prepare('SELECT rowid FROM box_fts_probe WHERE box_fts_probe MATCH ?')
    .bind('design').all();
  expect(tags.results).toHaveLength(1);
});
