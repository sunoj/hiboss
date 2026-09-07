// Differential tests for server and CLI publication error pointers.
// Exports no runtime API; compares both validators on the same documents.
// Dependencies: vitest, panel-runtime validators, the shared chart fixture, and hiboss CLI.
/// <reference types="node" />

import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import boundChart from '../fixtures/bound-chart.json' with { type: 'json' };
import { validateAnswerSchema, validateAnswers, validatePanelPublication } from '../src/index.js';

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const cliBinary = join(process.env.CARGO_TARGET_DIR ?? join(repositoryRoot, 'cli/target'), 'debug/hiboss');

type Publication = Record<string, unknown>;

function clonePublication(): Publication {
  return structuredClone(boundChart) as Publication;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error('expected object');
  return value as Record<string, unknown>;
}

function caseDocuments(): readonly [string, Publication][] {
  const badChartBinding = clonePublication();
  const taskSchema = asRecord(asRecord(badChartBinding.stateSchema).properties).task;
  asRecord(asRecord(taskSchema).properties).series = { type: 'number' };
  asRecord(asRecord(badChartBinding.initialState).task).series = 12;

  const unknownChild = clonePublication();
  asRecord(asRecord(asRecord(unknownChild.spec).elements).main).children = ['missing'];

  const invalidInitialSeriesItem = clonePublication();
  const task = asRecord(asRecord(invalidInitialSeriesItem.stateSchema).properties).task;
  asRecord(asRecord(task).properties).series = { type: 'array', items: { type: 'number' } };
  asRecord(asRecord(invalidInitialSeriesItem.initialState).task).series = [12, null, 18];

  return [
    ['bad chart binding', badChartBinding],
    ['unknown child', unknownChild],
    ['null in a number-only series', invalidInitialSeriesItem],
  ];
}

function serverPointer(publication: Publication): string {
  const publicationResult = validatePanelPublication(publication);
  if (!publicationResult.ok) return publicationResult.error.path;
  const schemaResult = validateAnswerSchema(publication.stateSchema);
  if (!schemaResult.ok) return `/stateSchema${schemaResult.error.path}`;
  const initialStateResult = validateAnswers(schemaResult.value, publication.initialState);
  if (!initialStateResult.ok) return `/initialState${initialStateResult.error.path}`;
  throw new Error('server unexpectedly accepted the differential case');
}

function cliPointer(publication: Publication): string {
  const directory = mkdtempSync(join(tmpdir(), 'hiboss-pointer-parity-'));
  const file = join(directory, 'publication.json');
  writeFileSync(file, JSON.stringify(publication));
  try {
    execFileSync(cliBinary, ['panel', 'validate', file], {
      cwd: repositoryRoot,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
      encoding: 'utf8',
    });
  } catch (error) {
    const stderr = typeof error === 'object' && error !== null && 'stderr' in error ? String(error.stderr) : '';
    const match = stderr.match(/Error: \S+ at (\/[^:]+):/);
    if (match?.[1] !== undefined) return match[1];
    throw new Error(`CLI validation did not report a pointer: ${stderr}`);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
  throw new Error('CLI unexpectedly accepted the differential case');
}

describe('server and CLI publication pointer parity', () => {
  it.each(caseDocuments())('reports the same document-rooted pointer for %s', (_name, publication) => {
    expect(serverPointer(publication)).toBe(cliPointer(publication));
  });
});
