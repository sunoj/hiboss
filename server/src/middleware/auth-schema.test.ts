// Checks the narrow missing-schema fallback and once-per-isolate warning.
// Uses typed middleware stubs; deployment.e2e.test.ts covers real D1 and SELF.
import { expect, it, vi } from 'vitest';
import { apiAuth } from './auth';

function failingContext(message: string): {
  context: Parameters<typeof apiAuth>[0];
  queries: string[];
} {
  const queries: string[] = [];
  const context = {
    req: { header: () => 'Bearer schema-test-token' },
    env: { DB: { prepare(sql: string) {
      queries.push(sql);
      return { bind: () => ({ first: async () => {
        if (sql.includes('FROM agent_keys')) throw new Error(message);
        return null;
      } }) };
    } } },
    text: (body: string, status: number) => new Response(body, { status }),
  } as unknown as Parameters<typeof apiAuth>[0];
  return { context, queries };
}

it('logs missing agent_keys once while retrying credential lookup on every request', async () => {
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  try {
    const { context, queries } = failingContext('D1_ERROR: no such table: agent_keys: SQLITE_ERROR');
    for (let i = 0; i < 2; i++) {
      expect((await apiAuth(context, async () => {}))?.status).toBe(401);
    }
    expect(queries).toHaveLength(4);
    expect(queries.filter(sql => sql.includes('FROM agent_keys'))).toHaveLength(2);
    expect(warn).toHaveBeenCalledTimes(1);
    expect(warn).toHaveBeenCalledWith('agent_keys table unavailable; using legacy agent authentication until migration 0045');
  } finally {
    warn.mockRestore();
  }
});

it('propagates unrelated database errors without attempting legacy authentication', async () => {
  for (const message of ['D1_ERROR: database unavailable', 'D1_ERROR: no such table: api_keys: SQLITE_ERROR']) {
    const { context, queries } = failingContext(message);
    await expect(apiAuth(context, async () => {})).rejects.toThrow(message);
    expect(queries).toHaveLength(1);
  }
});
