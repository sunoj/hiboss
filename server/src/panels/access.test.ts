// Unit coverage for default panel publication target selection.
// Exercises defaultBossId without D1 or authentication dependencies.
import { expect, it } from 'vitest';
import { defaultBossId, type ResolvedBoss } from './access';

const admin: ResolvedBoss = { id: 'admin', name: 'Ming', role: 'admin' };
const manager: ResolvedBoss = { id: 'manager', name: 'Island', role: 'manager' };
const viewer: ResolvedBoss = { id: 'viewer', name: 'Viewer', role: 'viewer' };

it.each([
  { rows: [], expected: null },
  { rows: [admin], expected: admin.id },
  { rows: [manager], expected: manager.id },
  { rows: [viewer], expected: viewer.id },
  { rows: [manager, admin, viewer], expected: admin.id },
  { rows: [admin, manager], expected: admin.id },
  { rows: [manager, viewer], expected: null },
  { rows: [admin, { ...admin, id: 'other-admin' }], expected: null },
])('selects $expected for $rows', ({ rows, expected }) => {
  expect(defaultBossId(rows)).toBe(expected);
});
