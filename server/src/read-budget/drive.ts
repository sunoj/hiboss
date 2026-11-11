// Drives one registered read path against a metered D1 and reduces its statements to calls.
// Exports driveStream (SSE/long-poll routes), driveRequest (endpoints), driveTask (cron steps).
// Depends on the Worker entry, cloudflare:test execution contexts, and the injected 25 ms poll.

import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test';
import worker from '../index';
import type { Env } from '../types';
import { MeterLog, meterDatabase, type Statement } from './meter';

/** Rows read by one driven path: the connect phase and each later call (poll, request or run). */
export interface Measurement {
  connect: number;
  calls: number[];
  heaviest: Statement | null;
  /** Loops only: `<rows> <statement head>` for each connect-phase statement, for the report. */
  connectStatements?: string[];
}

// Test polls sleep 25 ms (vitest.config.mts); statements of one poll run back to back.
const POLL_GAP_MS = 15;

/** Opens a stream route and meters its connect phase plus `polls` idle polls. */
export async function driveStream(request: () => Request, polls: number): Promise<Measurement> {
  const log = new MeterLog(POLL_GAP_MS);
  let lastEnd = 0;
  const stop = () => {
    lastEnd = log.statements.reduce((end, statement) => Math.max(end, statement.ended), lastEnd);
    return log.iterations().length > polls && Date.now() - lastEnd >= POLL_GAP_MS;
  };
  await fetchMetered(request(), log, stop);
  const [connect = [], ...rest] = log.iterations();
  if (rest.length < polls) throw new Error(`stream ended after ${rest.length} of ${polls} polls`);
  const connectStatements = connect.map((statement) => `${statement.rows} ${statement.sql.replace(/\s+/g, ' ').slice(0, 70)}`);
  return { ...summarize(log, sum(connect), rest.slice(0, polls).map(sum)), connectStatements };
}

/** Sends `request` `times` times; each call is the rows read by one request, waitUntil work included. */
export async function driveRequest(request: () => Request, times = 3): Promise<Measurement> {
  const log = new MeterLog(POLL_GAP_MS);
  const calls: number[] = [];
  for (let index = 0; index < times; index += 1) {
    const before = log.total();
    const response = await fetchMetered(request(), log);
    if (response.status >= 400) throw new Error(`${request().url} answered ${response.status}`);
    calls.push(log.total() - before);
  }
  return summarize(log, 0, calls);
}

/** Runs a scheduled step `times` times on a metered env; each call is one run's rows. */
export async function driveTask(task: (metered: Env) => Promise<unknown>, times = 2): Promise<Measurement> {
  const log = new MeterLog(POLL_GAP_MS);
  const calls: number[] = [];
  for (let index = 0; index < times; index += 1) {
    const before = log.total();
    await task(meteredEnv(log));
    calls.push(log.total() - before);
  }
  return summarize(log, 0, calls);
}

export function meteredEnv(log: MeterLog, stop?: () => boolean): Env {
  return { ...env, DB: meterDatabase(env.DB, log, stop) } as unknown as Env;
}

async function fetchMetered(request: Request, log: MeterLog, stop?: () => boolean): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, meteredEnv(log, stop), ctx);
  await response.arrayBuffer();
  await waitOnExecutionContext(ctx);
  return response;
}

function summarize(log: MeterLog, connect: number, calls: number[]): Measurement {
  const heaviest = log.statements.reduce<Statement | null>(
    (top, statement) => (!top || statement.rows > top.rows ? statement : top), null);
  return { connect, calls, heaviest };
}

function sum(statements: Statement[]): number {
  return statements.reduce((total, statement) => total + statement.rows, 0);
}
