// Agent callbacks and boss push notification integration tests.
// Shares root database and fetch cleanup across callback and device scenarios.

import './notify-tests/callbacks';
import './notify-tests/boss';
import { afterEach, beforeAll, vi } from 'vitest';
import { seedDatabase } from './test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

afterEach(() => {
  vi.unstubAllGlobals();
});
