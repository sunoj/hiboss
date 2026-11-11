// Read-budget gate: every registered repeated read path stays within its rows-read budget,
// and its reads stay flat when the history doubles (N → 2N rows), on a production-shaped D1.
// Depends on read-paths.ts, repeat-sites.ts, the metered drivers and the shared test schema.

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase } from '../test-helpers';
import type { Measurement } from './drive';
import { READ_PATHS, type ReadPath } from './read-paths';
import { REPEAT_SITES } from './repeat-sites';
import { seedHistoryLayer, seedLiveState } from './seed';

// Rows a path may add when the history doubles: index depth and fixture noise, never a scan.
const GROWTH_SLACK = 25;
const measured = new Map<string, Measurement[]>();
const failures = new Map<string, string>();

beforeAll(async () => {
  await seedDatabase();
  await seedLiveState();
  await seedHistoryLayer(0);
}, 120_000);

afterAll(() => {
  for (const path of READ_PATHS) {
    const [n, n2] = measured.get(path.id) ?? [];
    console.info(`READ_BUDGET ${JSON.stringify({ id: path.id, budget: path.budget, connectBudget: path.connectBudget,
      n: n && summary(n), n2: n2 && summary(n2), heaviest: n2?.heaviest && compact(n2.heaviest.sql, n2.heaviest.rows),
      connectStatements: n?.connectStatements })}`);
  }
});

describe('read-budget gate', () => {
  it('measures every registered path at N history rows', async () => measureAll(), 120_000);

  it('doubles the history', async () => seedHistoryLayer(1), 120_000);

  it('measures every registered path at 2N history rows', async () => measureAll(), 120_000);

  it('meters every registered repeat site through a read path', () => {
    const ids = new Set(READ_PATHS.map((path) => path.id));
    for (const site of REPEAT_SITES) for (const path of site.paths) expect(ids.has(path), `${site.id} → ${path}`).toBe(true);
    const metered = new Set(REPEAT_SITES.flatMap((site) => site.paths));
    for (const path of READ_PATHS.filter((entry) => entry.kind === 'loop')) expect(metered.has(path.id), path.id).toBe(true);
  });

  describe.each(READ_PATHS.map((path) => [path.id, path] as const))('%s', (_, path) => {
    it('stays within its per-call budget at N and 2N', () => {
      const [n, n2] = results(path);
      expect(Math.max(...n.calls, ...n2.calls), 'rows per call').toBeLessThanOrEqual(path.budget);
      if (path.connectBudget !== undefined) {
        expect(Math.max(n.connect, n2.connect), 'connect rows').toBeLessThanOrEqual(path.connectBudget);
      }
    });

    it(path.exemption ? 'stays under its exemption ceiling' : 'does not grow with history', () => {
      const [n, n2] = results(path);
      if (path.exemption) {
        expect(Math.max(...n2.calls, n2.connect), path.exemption.reason).toBeLessThanOrEqual(path.exemption.ceiling);
        return;
      }
      expect(Math.max(...n2.calls) - Math.max(...n.calls), 'rows per call growth').toBeLessThanOrEqual(GROWTH_SLACK);
      expect(n2.connect - n.connect, 'connect rows growth').toBeLessThanOrEqual(GROWTH_SLACK);
    });
  });
});

/** Measures every path; a path that fails to run fails its own tests, not the others'. */
async function measureAll(): Promise<void> {
  for (const path of READ_PATHS) {
    try {
      measured.set(path.id, [...(measured.get(path.id) ?? []), await path.measure()]);
    } catch (error) {
      failures.set(path.id, String(error));
    }
  }
  expect(Object.fromEntries(failures)).toEqual({});
}

function results(path: ReadPath): [Measurement, Measurement] {
  const [n, n2] = measured.get(path.id) ?? [];
  if (!n || !n2) throw new Error(`${path.id} was not measured at N and 2N: ${failures.get(path.id) ?? ''}`);
  return [n, n2];
}

function summary(measurement: Measurement): { connect: number; calls: number[] } {
  return { connect: measurement.connect, calls: measurement.calls };
}

function compact(sql: string, rows: number): string {
  return `${rows} rows: ${sql.replace(/\s+/g, ' ').slice(0, 160)}`;
}
