#!/usr/bin/env node
// Daily production D1 rows-read detector: reads `wrangler d1 insights` for the last day and
// alerts through `hiboss send` when total or per-query reads cross the documented thresholds.
// No dependencies; WRANGLER / HIBOSS override the commands. Exit 0 healthy, 1 breach, 2 unreadable.

import { execFileSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// Thresholds per day; derivation in docs/reference/d1-read-budget.md.
export const THRESHOLDS = {
  totalRowsRead: 250_000_000,
  queryRowsRead: 50_000_000,
  scanAvgRowsRead: 2_000,
  scanRuns: 5_000,
};
const DATABASE = process.env.D1_DATABASE ?? 'hiboss-db';
const LIMIT = 100;

function command(variable, fallback) {
  const words = (process.env[variable] ?? fallback).trim().split(/\s+/);
  return { file: words[0], args: words.slice(1) };
}

function insights(sortBy) {
  const wrangler = command('WRANGLER', 'npx wrangler');
  const args = [...wrangler.args, 'd1', 'insights', DATABASE, '--time-period', '1d',
    '--sort-by', sortBy, '--limit', String(LIMIT), '--json'];
  const output = execFileSync(wrangler.file, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const rows = JSON.parse(output.slice(output.indexOf('[')));
  if (!Array.isArray(rows)) throw new Error(`insights --sort-by ${sortBy} did not return a JSON array`);
  return rows;
}

/** Merges both rankings by statement text; the same statement appears once. */
export function mergeInsights(...lists) {
  const byQuery = new Map();
  for (const row of lists.flat()) byQuery.set(row.query, row);
  return [...byQuery.values()];
}

/** Breach lines for one day of insights; empty when healthy. */
export function evaluate(rows, limits = THRESHOLDS) {
  const breaches = [];
  const total = rows.reduce((sum, row) => sum + (row.totalRowsRead ?? 0), 0);
  if (total > limits.totalRowsRead) {
    breaches.push(`total ${format(total)} rows read/day > ${format(limits.totalRowsRead)}`);
  }
  for (const row of rows) {
    const label = `${format(row.totalRowsRead)} rows (${format(row.numberOfTimesRun)} runs × `
      + `${format(row.avgRowsRead)} avg): ${statement(row.query)}`;
    if (row.totalRowsRead > limits.queryRowsRead) breaches.push(`query ${label}`);
    else if (row.avgRowsRead > limits.scanAvgRowsRead && row.numberOfTimesRun > limits.scanRuns) {
      breaches.push(`hot scan ${label}`);
    }
  }
  return { total, breaches };
}

function format(value) {
  return Math.round(value ?? 0).toLocaleString('en-US');
}

function statement(sql) {
  const text = String(sql).replace(/\s+/g, ' ').trim();
  return text.length > 140 ? `${text.slice(0, 140)}…` : text;
}

function alert(title, content) {
  const hiboss = command('HIBOSS', 'hiboss');
  try {
    execFileSync(hiboss.file, [...hiboss.args, 'send', title, '--priority', 'high', '--content', content],
      { stdio: ['ignore', 'inherit', 'inherit'] });
  } catch (error) {
    console.error(`d1-read-watch: hiboss send failed: ${error?.message ?? error}`);
  }
}

function main() {
  let rows;
  try {
    rows = mergeInsights(insights('reads'), insights('count'));
  } catch (error) {
    const reason = String(error?.stderr || error?.message || error).trim().slice(0, 600);
    console.error(`d1-read-watch: cannot read insights: ${reason}`);
    alert('D1 read watch could not read insights', `\`wrangler d1 insights ${DATABASE}\` failed:\n\n${reason}`);
    return 2;
  }
  const { total, breaches } = evaluate(rows);
  if (breaches.length === 0) {
    console.log(`d1-read-watch: ok ${format(total)} rows read in 1d across ${rows.length} statements`);
    return 0;
  }
  console.error(`d1-read-watch: BREACH\n${breaches.join('\n')}`);
  alert(`D1 rows read over budget: ${format(total)} in 1d`,
    `Thresholds: ${JSON.stringify(THRESHOLDS)}\n\n${breaches.map((line) => `- ${line}`).join('\n')}`);
  return 1;
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main();
